#include "HeifImage.h"
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QCoreApplication>
#include <memory>
#include <stdexcept>
#ifdef IMAGECLASSIFIER_HEIF
#include <libheif/heif.h>
#include <windows.h>
namespace {
[[noreturn]] void fail(const QString &s){throw std::runtime_error(s.toUtf8().constData());}
struct Api {
    HMODULE library=nullptr;
#define API(name) decltype(&name) name=nullptr
    API(heif_context_alloc);API(heif_context_free);API(heif_context_read_from_memory_without_copy);
    API(heif_context_get_primary_image_handle);API(heif_image_handle_release);
    API(heif_image_handle_get_width);API(heif_image_handle_get_height);
    API(heif_decode_image);API(heif_image_release);API(heif_image_get_plane_readonly);
    API(heif_image_get_width);API(heif_image_get_height);
#undef API
    Api(){
        for(const auto &base:{QCoreApplication::applicationDirPath()+"/media/heif",QString(APP_PROJECT_DIR)+"/.tools/media/heif"}){
            const auto path=QDir::toNativeSeparators(base+"/heif.dll");
            library=LoadLibraryExW(reinterpret_cast<LPCWSTR>(path.utf16()),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
            if(library)break;
        }
        if(!library)fail("HEIC 解码组件不可用，请运行 Setup-Media.ps1 安装媒体组件");
#define LOAD(name) name=reinterpret_cast<decltype(name)>(GetProcAddress(library,#name));if(!name)fail("HEIC 解码组件版本不兼容")
        LOAD(heif_context_alloc);LOAD(heif_context_free);LOAD(heif_context_read_from_memory_without_copy);
        LOAD(heif_context_get_primary_image_handle);LOAD(heif_image_handle_release);
        LOAD(heif_image_handle_get_width);LOAD(heif_image_handle_get_height);LOAD(heif_decode_image);
        LOAD(heif_image_release);LOAD(heif_image_get_plane_readonly);LOAD(heif_image_get_width);LOAD(heif_image_get_height);
#undef LOAD
    }
};
Api &api(){static Api instance;return instance;}
void check(heif_error error){if(error.code!=heif_error_Ok)fail("HEIC 解码失败："+QString::fromUtf8(error.message));}
struct Image {
    QByteArray data;
    std::unique_ptr<heif_context,decltype(&heif_context_free)> context{nullptr,api().heif_context_free};
    std::unique_ptr<heif_image_handle,decltype(&heif_image_handle_release)> handle{nullptr,api().heif_image_handle_release};
    explicit Image(const QString &path){
        QFile f(path);if(!f.open(QIODevice::ReadOnly)||f.size()>256*1024*1024)fail("无法读取 HEIC 或文件超过 256 MB");
        data=f.readAll();context.reset(api().heif_context_alloc());if(!context)fail("无法分配 HEIC 解码器");
        check(api().heif_context_read_from_memory_without_copy(context.get(),data.constData(),data.size(),nullptr));
        heif_image_handle *h=nullptr;check(api().heif_context_get_primary_image_handle(context.get(),&h));handle.reset(h);
        const auto s=size();if(s.width()<=0||s.height()<=0||qint64(s.width())*s.height()>160000000)fail("HEIC 图片尺寸无效或过大");
    }
    QSize size()const{return {api().heif_image_handle_get_width(handle.get()),api().heif_image_handle_get_height(handle.get())};}
};
}
#endif
bool HeifImage::supportedPath(const QString &path){const auto ext=QFileInfo(path).suffix().toLower();return ext=="heic"||ext=="heif";}
QSize HeifImage::size(const QString &path){
#ifdef IMAGECLASSIFIER_HEIF
    return Image(path).size();
#else
    throw std::runtime_error("HEIC 解码组件未安装，请运行 Setup-Media.ps1 后重新构建");
#endif
}
QImage HeifImage::read(const QString &path,int maxEdge){
#ifdef IMAGECLASSIFIER_HEIF
    Image file(path);heif_image *decoded=nullptr;
    // libheif applies HEIF rotation/mirroring by default. Output is straight RGBA.
    check(api().heif_decode_image(file.handle.get(),&decoded,heif_colorspace_RGB,heif_chroma_interleaved_RGBA,nullptr));
    std::unique_ptr<heif_image,decltype(&heif_image_release)> image(decoded,api().heif_image_release);
    int stride=0;const auto *plane=api().heif_image_get_plane_readonly(decoded,heif_channel_interleaved,&stride);
    const auto width=api().heif_image_get_width(decoded,heif_channel_interleaved),height=api().heif_image_get_height(decoded,heif_channel_interleaved);
    if(!plane||width<=0||height<=0)throw std::runtime_error("HEIC 图片无有效像素");
    QImage view(plane,width,height,stride,QImage::Format_RGBA8888);
    return maxEdge>0&&qMax(width,height)>maxEdge?view.scaled(maxEdge,maxEdge,Qt::KeepAspectRatio,Qt::SmoothTransformation):view.copy();
#else
    throw std::runtime_error("HEIC 解码组件未安装，请运行 Setup-Media.ps1 后重新构建");
#endif
}
