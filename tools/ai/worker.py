"""Offline portrait proposals and bounded, user-specific crop learning.

JSON lines on stdin/stdout; diagnostics go to stderr. The fixed visual encoders
are never trained here. The personal ridge model and case memory use only the
most recent 100 successful export operations.
"""
import argparse
from collections import OrderedDict
import hashlib
import json
import math
from pathlib import Path
import sys
import stat
import time

import cv2
import numpy as np
import onnxruntime as ort

VERSION = 'portrait-v1'
RECORD_LIMIT = 100
MIN_BATCH = 5

def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))

def atomic_json(path, value):
    path = Path(path)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, allow_nan=False), encoding='utf-8')
    temp.replace(path)

def unit(vector):
    vector = np.asarray(vector, dtype=np.float64)
    return vector / max(float(np.linalg.norm(vector)), 1e-9)

def xyxy(spec):
    return np.array([spec['x'], spec['y'], spec['x'] + spec['w'], spec['y'] + spec['h']], dtype=float)

def area(box):
    return max(0., box[2] - box[0]) * max(0., box[3] - box[1])

def intersection(a, b):
    return area([max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])])

def points_to_canvas(points, frame):
    p = np.asarray(points, dtype=float) * [frame['width'], frame['height']]
    a, b, c, d, tx, ty = frame['transform']
    matrix = np.array([[a, c], [b, d]])
    return (p @ matrix.T + [tx, ty]) / [frame['canvasWidth'], frame['canvasHeight']]

def canvas_person(person, frame):
    x1, y1, x2, y2 = person['box']
    corners = points_to_canvas([[x1,y1],[x2,y1],[x1,y2],[x2,y2]], frame)
    box = np.concatenate([corners.min(axis=0), corners.max(axis=0)])
    return dict(box=box, points=points_to_canvas(person['points'], frame),
                scores=np.asarray(person['scores']), confidence=person['confidence'])

def relative_crop(box, person):
    p = person['box']; size = np.maximum(p[2:] - p[:2], .015)
    return (np.asarray(box) - np.tile(p[:2], 2)) / np.tile(size, 2)

def restore_crop(relative, person):
    p = person['box']; size = np.maximum(p[2:] - p[:2], .015)
    return np.asarray(relative) * np.tile(size, 2) + np.tile(p[:2], 2)

def geometric_features(person, frame):
    box, points, scores = person['box'], person['points'], person['scores']
    size = np.maximum(box[2:] - box[:2], .015)
    center = (box[2:] + box[:2]) / 2
    def height(indices):
        visible = [points[i, 1] for i in indices if scores[i] > .35]
        return float((np.mean(visible) - box[1]) / size[1]) if visible else -1.
    return np.array([1., size[0], size[1], *center,
        np.clip(math.log(size[0] * frame['canvasWidth'] / (size[1] * frame['canvasHeight'])), -2, 2),
        height([0,1,2]), height([5,6]), height([11,12]), height([15,16])], dtype=float)

def crop_kind(box, person):
    # Separate tight portraits from medium and full-body framing.
    relative = relative_crop(box, person)
    return 'close' if relative[3] < .43 else 'half' if relative[3] < .79 else 'full'

def select_person(people, crop=None):
    if not people:
        return None
    if crop is None:
        return max(people, key=lambda p: area(p['box']) * (.7 + .3 * p['confidence']))
    def score(p):
        overlap = intersection(crop, p['box']) / max(area(crop), 1e-6)
        center = (p['box'][:2] + p['box'][2:]) / 2
        crop_center = (crop[:2] + crop[2:]) / 2
        face = p['points'][0]
        contains_face = p['scores'][0] > .35 and crop[0] <= face[0] <= crop[2] and crop[1] <= face[1] <= crop[3]
        return overlap + .8 * contains_face - .25 * np.linalg.norm(center - crop_center)
    return max(people, key=score)

class Vision:
    def __init__(self, models):
        options = ort.SessionOptions()
        options.intra_op_num_threads = 4
        options.inter_op_num_threads = 1
        self.sessions = {name: ort.InferenceSession(str(models / (name + '.onnx')), sess_options=options,
                         providers=['CPUExecutionProvider']) for name in ('person', 'pose', 'features')}
        self.cache = OrderedDict()

    def infer(self, name, image):
        session = self.sessions[name]
        tensor = np.ascontiguousarray(image.transpose(2,0,1)[None], dtype=np.float32)
        return session.run(None, {session.get_inputs()[0].name: tensor})

    def analyze(self, path):
        data = Path(path).read_bytes()
        key = hashlib.sha256(data).hexdigest()
        if key in self.cache:
            self.cache.move_to_end(key)
            return self.cache[key]
        image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError('无法读取学习用图片')
        height, width = image.shape[:2]
        scale = min(640 / width, 640 / height)
        small = cv2.resize(image, (max(1,int(width*scale)),max(1,int(height*scale))))
        padded = np.full((640,640,3), 114, np.uint8)
        padded[:small.shape[0], :small.shape[1]] = small
        detections = self.infer('person', padded)[0][0]
        detections = sorted([x for x in detections if x[4] >= .35], key=lambda x: -float(x[4]))[:12]
        people = []
        for detection in detections:
            box = detection[:4].astype(float) / scale
            box[[0,2]] = np.clip(box[[0,2]], 0, width)
            box[[1,3]] = np.clip(box[[1,3]], 0, height)
            if box[2]-box[0] < 12 or box[3]-box[1] < 12:
                continue
            center = (box[:2] + box[2:]) / 2
            extent = (box[2:] - box[:2]) * 1.25
            ratio = 288 / 384
            if extent[0] / extent[1] > ratio:
                extent[1] = extent[0] / ratio
            else:
                extent[0] = extent[1] * ratio
            matrix = np.array([[288/extent[0],0,144-center[0]*288/extent[0]],
                               [0,384/extent[1],192-center[1]*384/extent[1]]], dtype=np.float32)
            region = cv2.warpAffine(image, matrix, (288,384), flags=cv2.INTER_LINEAR)
            # This exported RTMPose model follows the original BGR preprocessing.
            region = (region.astype(np.float32) - [123.675,116.28,103.53]) / [58.395,57.12,57.375]
            sx, sy = self.infer('pose', region)
            sx, sy = sx[0], sy[0]
            coords = np.stack([sx.argmax(axis=1),sy.argmax(axis=1)], axis=1) / 2.
            scores = np.minimum(sx.max(axis=1), sy.max(axis=1))
            points = coords / [288,384] * extent + center - extent/2
            people.append({'box': (box / [width,height,width,height]).tolist(),
                           'points': (points / [width,height]).tolist(), 'scores': scores.tolist(),
                           'confidence': float(detection[4])})
        # Fixed-shape DINOv2 input, preserving the whole composition with padding.
        rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        scale = min(224/width,224/height)
        rw, rh = max(1,round(width*scale)),max(1,round(height*scale))
        resized = cv2.resize(rgb,(rw,rh), interpolation=cv2.INTER_AREA).astype(np.float32)/255.
        feature_image = np.zeros((224,224,3),np.float32)
        x,y=(224-rw)//2,(224-rh)//2
        feature_image[y:y+rh,x:x+rw] = (resized-[.485,.456,.406])/[.229,.224,.225]
        embedding = unit(self.infer('features',feature_image)[0][0]).tolist()
        result={'version':VERSION,'people':people,'embedding':embedding}
        self.cache[key]=result
        while len(self.cache)>8:
            self.cache.popitem(last=False)
        return result

class Learner:
    def __init__(self, data):
        self.data = data
        self.memory=[]
        self.weights={}
        self.signature=''
        self.batch_signature=''
        self.batch_count=0
        path=data/'preferences.json'
        if path.exists():
            try:
                state=read_json(path)
                if state.get('version')==VERSION:
                    self.weights=state.get('weights',{})
                    self.batch_signature=state.get('signature','')
                    self.batch_count=state.get('operations',0)
            except (ValueError,OSError):
                pass

    def records(self):
        recent=self.data/'recent'
        if not recent.exists():return []
        paths=[]
        for p in recent.glob('r-*/record.json'):
            try:
                attributes=getattr(p.parent.lstat(),'st_file_attributes',0)
                if not p.parent.is_symlink() and not attributes & getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',1024):
                    paths.append(p)
            except OSError:
                continue
        return sorted(paths)[-RECORD_LIMIT:]

    def refresh(self, vision, force=False):
        paths=self.records()
        signature=hashlib.sha256('|'.join(p.parent.name for p in paths).encode()).hexdigest()
        if signature==self.signature and not force:
            return len(paths),len(self.memory),False
        memory=[]
        for path in paths:
            try:
                record=read_json(path)
                cached=path.parent/'analysis.json'
                analysis=read_json(cached) if cached.exists() else None
                if not analysis or analysis.get('version')!=VERSION:
                    analysis=vision.analyze(path.parent/'source.jpg')
                    if path.exists():atomic_json(cached,analysis)
                for crop in record['crops']:
                    f=crop['frame']
                    people=[canvas_person(p,f) for p in analysis['people']]
                    target=xyxy(crop)
                    p=select_person(people,target)
                    if p is None or intersection(p['box'],target)<.02*area(p['box']):continue
                    relative=relative_crop(target,p)
                    if not np.isfinite(relative).all() or np.max(np.abs(relative))>4:continue
                    memory.append({'operation':record['id'],'embedding':analysis['embedding'],
                        'features':geometric_features(p,f).tolist(),'relative':relative.tolist(),
                        'kind':crop_kind(target,p),'ratio':crop.get('ratio',0),'angle':crop.get('angle',0)})
            except (OSError,ValueError,KeyError,cv2.error):
                # A record can be evicted while a background batch is reading it.
                continue
        self.memory=memory
        self.signature=signature
        operations=len(set(s['operation'] for s in memory))
        trained=False
        # Each successful operation enters case memory immediately. Batch-fit the
        # small regularized model after five new operations (and every full ring).
        if operations>=MIN_BATCH and (force or not self.weights or len(paths)-self.batch_count>=5 or len(paths)==RECORD_LIMIT):
            weights={}
            for kind in ('close','half','full'):
                samples=[s for s in memory if s['kind']==kind]
                if len(set(s['operation'] for s in samples))<MIN_BATCH:continue
                x=np.array([s['features'] for s in samples]);y=np.array([s['relative'] for s in samples])
                # Equal total weight per export operation even when it has many children.
                counts={s['operation']:sum(t['operation']==s['operation'] for t in samples) for s in samples}
                w=np.array([1/counts[s['operation']] for s in samples])
                penalty=np.eye(x.shape[1])*2.;penalty[0,0]=.01
                coefficients=np.linalg.solve(x.T@(w[:,None]*x)+penalty,x.T@(w[:,None]*y))
                weights[kind]=coefficients.tolist()
            state={'version':VERSION,'signature':signature,'operations':len(paths),'weights':weights,'examples':len(memory)}
            self.data.mkdir(parents=True,exist_ok=True)
            atomic_json(self.data/'preferences.json',state)
            self.weights=weights;self.batch_count=len(paths);self.batch_signature=signature;trained=True
        elif operations<MIN_BATCH:
            self.weights={}
            if (self.data/'preferences.json').exists():
                atomic_json(self.data/'preferences.json', {'version':VERSION,'weights':{},'operations':0,'signature':signature})
        return len(paths),len(memory),trained

    def proposal(self, analysis, frame, spec):
        people=[canvas_person(p,frame) for p in analysis['people']]
        # An explicitly edited draft provides subject intent on manual re-suggestion.
        person=select_person(people,xyxy(spec) if spec.get('touched') else None)
        if person is None:
            raise ValueError('未可靠识别到人物，保留当前裁剪框')
        features=geometric_features(person,frame)
        embedding=np.array(analysis['embedding'])
        ratio=float(spec.get('ratio',0))
        matches=[]
        for sample in self.memory:
            similarity=float(embedding@sample['embedding'])
            geometry=float(np.linalg.norm(features[1:]-np.array(sample['features'])[1:]))
            ratio_penalty=.12 if bool(ratio)!=bool(sample['ratio']) else 0.
            if ratio>0 and sample['ratio']>0:ratio_penalty+=.15*abs(math.log(ratio/sample['ratio']))
            angle_penalty=.1*min(1.,abs(math.remainder(float(spec.get('angle',0))-sample['angle'],360))/45)
            score=similarity-.12*geometry-ratio_penalty-angle_penalty
            if similarity>.45:matches.append((score,sample))
        matches.sort(key=lambda x:-x[0]);matches=matches[:8]
        kind=crop_kind(xyxy(spec),person) if spec.get('touched') else (matches[0][1]['kind'] if matches else 'full')
        # Start with content-preserving framing, then learn the user's deliberate
        # crop boundaries. This does not try to infer missing/off-image anatomy.
        default={'close':[-.12,-.05,1.12,.44],'half':[-.08,-.04,1.08,.74],'full':[-.06,-.04,1.06,1.04]}[kind]
        relatives=[np.array(default,dtype=float)]
        same=[(score,s) for score,s in matches if s['kind']==kind]
        if same:
            ws=np.exp(np.array([x[0] for x in same])*8);ws/=ws.sum()
            memory_crop=sum(w*np.array(s['relative']) for w,(_,s) in zip(ws,same))
            relatives.insert(0,memory_crop)
            if kind in self.weights:
                regression=features@np.array(self.weights[kind])
                relatives.insert(0,.75*memory_crop+.25*regression)
        elif kind in self.weights:
            relatives.insert(0,features@np.array(self.weights[kind]))
        candidates=[]
        for index,relative in enumerate(relatives):
            box=restore_crop(np.clip(relative,-2,3),person)
            if box[2]<=box[0] or box[3]<=box[1]:continue
            box=fit_box(box,ratio,frame)
            if area(box)<.001:continue
            # Keep confidently located face landmarks unless the user explicitly
            # chose a crop that excludes them (re-suggestion on an edited draft).
            face=person['points'][:5][person['scores'][:5]>.45]
            if len(face) and not spec.get('touched'):
                if not np.all((face[:,0]>=box[0])&(face[:,0]<=box[2])&(face[:,1]>=box[1])&(face[:,1]<=box[3])):
                    continue
            candidates.append((index,box))
        if not candidates:
            raise ValueError('当前比例无法可靠保留人物，请手动调整')
        box=candidates[0][1]
        count=len(set(s['operation'] for s in self.memory))
        message=f'已应用智能裁剪 · 参考 {len(same)} 个相似裁剪' if same else '已应用智能裁剪 · 根据人物位置取景'
        return {'crop':{'x':float(box[0]),'y':float(box[1]),'w':float(box[2]-box[0]),'h':float(box[3]-box[1])},
                'message':message,'learningOperations':count,'modelVersion':VERSION,
                'protectedFace':person['points'][:5][person['scores'][:5]>.45].tolist() if not spec.get('touched') else []}

def fit_box(box,ratio,frame):
    box=np.asarray(box,dtype=float)
    center=(box[:2]+box[2:])/2
    size=np.maximum(box[2:]-box[:2],.02)
    if ratio>0:
        normalized=ratio*frame['canvasHeight']/frame['canvasWidth']
        if size[0]/size[1]<normalized:size[0]=size[1]*normalized
        else:size[1]=size[0]/normalized
    size/=max(1.,float(size.max()))
    center=np.clip(center,size/2,1-size/2)
    return np.concatenate([center-size/2,center+size/2])

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--models',type=Path,required=True);parser.add_argument('--data',type=Path,required=True)
    args=parser.parse_args();vision=None;learner=Learner(args.data)
    for line in sys.stdin:
        request={}
        try:
            request=json.loads(line)
            if vision is None:vision=Vision(args.models)
            count,examples,trained=learner.refresh(vision)
            if request['action']=='train':
                detail=f'偏好已更新（{examples} 个裁剪）' if trained else f'已纳入 {examples} 个有效裁剪'
                result={'message':f'最近记录 {count}/100 · '+detail}
            elif request['action']=='predict':
                result=learner.proposal(vision.analyze(request['image']),request['frame'],request['spec'])
            else:raise ValueError('未知智能裁剪请求')
        except Exception as e:
            print(f'{type(e).__name__}: {e}',file=sys.stderr,flush=True)
            result={'error':str(e)}
        result['token']=request.get('token','')
        print(json.dumps(result,ensure_ascii=False,allow_nan=False),flush=True)

if __name__=='__main__':
    main()
