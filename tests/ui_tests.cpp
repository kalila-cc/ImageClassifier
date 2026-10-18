#include <QGuiApplication>
#include <QQuickView>
#include <QQuickItem>
#include <QTest>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlApplicationEngine>
#include <QJSValue>
#include <QTemporaryDir>
#include <QDir>
#include <QImage>
#include "Backend.h"
#include "ImageProvider.h"

class CountingProvider : public ImageProvider {
public:
    using ImageProvider::ImageProvider;
    std::atomic_int requests{0};
    QImage requestImage(const QString &id,QSize *size,const QSize &requested) override {
        ++requests;
        return ImageProvider::requestImage(id,size,requested);
    }
};

class UiTests : public QObject {
    Q_OBJECT
private slots:
    void directoryBrowsingAndTargetSelection() {
        QTemporaryDir temp;const auto rootPath=temp.filePath("target"),first=rootPath+"/01",second=rootPath+"/02";
        QVERIFY(QDir().mkpath(first+"/child"));QVERIFY(QDir().mkpath(second));
        QImage photo(32,32,QImage::Format_RGB32);photo.fill(Qt::green);
        QVERIFY(photo.save(first+"/direct.png"));QVERIFY(photo.save(first+"/child/nested.png"));
        const auto database=temp.filePath("state/db.sqlite");Backend backend(database);
        backend.setTargetRoot(rootPath);QTRY_VERIFY_WITH_TIMEOUT(!backend.busy(),5000);
        QQmlApplicationEngine engine;engine.rootContext()->setContextProperty("backend",&backend);
        engine.addImageProvider("media",new ImageProvider(database));
        engine.load(QUrl::fromLocalFile(QString(TEST_UI_DIR)+"/../ui/Application.qml"));
        QVERIFY(!engine.rootObjects().isEmpty());auto *app=engine.rootObjects()[0];
        auto *window=qobject_cast<QQuickWindow*>(app);QVERIFY(window);QVERIFY(QTest::qWaitForWindowExposed(window));
        auto *tree=app->findChild<QQuickItem*>("directoryTree");QVERIFY(tree);
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,tree->mapToScene(QPointF(95,57)).toPoint());
        QCOMPARE(app->property("destination").toString(),first);
        QCOMPARE(backend.items().size(),0);QVERIFY(backend.sources().isEmpty());
        QTest::mouseDClick(window,Qt::LeftButton,Qt::NoModifier,tree->mapToScene(QPointF(95,57)).toPoint());
        QTRY_VERIFY_WITH_TIMEOUT(!backend.busy(),5000);QTRY_COMPARE(backend.items().size(),1);
        QCOMPARE(backend.items()[0].toMap()["name"].toString(),QString("direct.png"));
        QCOMPARE(app->property("browsingPath").toString(),first);
        QCOMPARE(app->property("destination").toString(),first);
        const auto id=backend.items()[0].toMap()["id"].toString();
        QVERIFY(QMetaObject::invokeMethod(app,"toggle",Q_ARG(QVariant,QVariant(id))));
        // Set 02 as the target without navigating away or clearing the photo selection.
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,tree->mapToScene(QPointF(95,135)).toPoint());
        QTRY_COMPARE(app->property("destination").toString(),second);
        QCOMPARE(app->property("browsingPath").toString(),first);QCOMPARE(backend.items().size(),1);
        QCOMPARE(app->property("selection").value<QJSValue>().toVariant().toList().size(),1);
        // In the large editor, a single click assigns the crop target without navigation.
        app->setProperty("largeMode",true);
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,tree->mapToScene(QPointF(95,18)).toPoint());
        QTest::qWait(500);
        QCOMPARE(app->property("destination").toString(),rootPath);
        QCOMPARE(app->property("browsingPath").toString(),first);
        QCOMPARE(backend.loadDraft(id)[0].toMap()["target"].toString(),rootPath);
        app->setProperty("largeMode",false);
        // Only double-clicking opens another work directory; no files are moved.
        QTest::mouseDClick(window,Qt::LeftButton,Qt::NoModifier,tree->mapToScene(QPointF(95,135)).toPoint());
        QTRY_VERIFY_WITH_TIMEOUT(!backend.busy(),5000);QTRY_COMPARE(backend.items().size(),0);
        QCOMPARE(app->property("browsingPath").toString(),second);QVERIFY(QFileInfo::exists(first+"/direct.png"));
        window->close();
    }
    void directoryContextActions() {
        QQuickView view;
        view.setSource(QUrl::fromLocalFile(QString(TEST_UI_DIR)+"/directory_tree.qml"));
        QCOMPARE(view.status(),QQuickView::Ready);view.show();QVERIFY(QTest::qWaitForWindowExposed(&view));
        auto *root=view.rootObject();
        auto *menu=root->findChild<QObject*>("directoryContextMenu");
        auto *create=root->findChild<QQuickItem*>("createDirectoryMenuItem");
        auto *rename=root->findChild<QQuickItem*>("renameDirectoryMenuItem");
        auto *open=root->findChild<QQuickItem*>("openDirectoryMenuItem");
        QVERIFY(menu&&create&&rename&&open);
        QTest::mouseClick(&view,Qt::RightButton,Qt::NoModifier,QPoint(100,57));
        QTRY_VERIFY(menu->property("visible").toBool());
        QCOMPARE(root->property("selections").toInt(),0);
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,create->mapToScene(QPointF(create->width()/2,create->height()/2)).toPoint());
        QTRY_COMPARE(root->property("createdUnder").toString(),QString("/root/a"));
        QTRY_VERIFY(!menu->property("visible").toBool());
        QTest::mouseClick(&view,Qt::RightButton,Qt::NoModifier,QPoint(100,96));
        QTRY_VERIFY(menu->property("visible").toBool());
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,rename->mapToScene(QPointF(rename->width()/2,rename->height()/2)).toPoint());
        QTRY_COMPARE(root->property("renamedPath").toString(),QString("/root/a/nested"));
        QCOMPARE(root->property("selections").toInt(),0);
        QTRY_VERIFY(!menu->property("visible").toBool());
        QTest::mouseClick(&view,Qt::RightButton,Qt::NoModifier,QPoint(100,18));
        QTRY_VERIFY(menu->property("visible").toBool());QVERIFY(rename->isEnabled());QVERIFY(create->isEnabled());
        QCOMPARE(root->property("contextName").toString(),QString("root"));
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,rename->mapToScene(QPointF(rename->width()/2,rename->height()/2)).toPoint());
        QTRY_COMPARE(root->property("renamedPath").toString(),QString("/root"));
        QTRY_VERIFY(!menu->property("visible").toBool());
        QTest::mouseClick(&view,Qt::RightButton,Qt::NoModifier,QPoint(100,57));
        QTRY_VERIFY(menu->property("visible").toBool());
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,open->mapToScene(QPointF(open->width()/2,open->height()/2)).toPoint());
        QTRY_COMPARE(root->property("openedPath").toString(),QString("/root/a"));
        QCOMPARE(root->property("selections").toInt(),0);
    }
    void directoryCollapse() {
        QQuickView view;
        view.setSource(QUrl::fromLocalFile(QString(TEST_UI_DIR)+"/directory_tree.qml"));
        QCOMPARE(view.status(),QQuickView::Ready);
        view.show();QVERIFY(QTest::qWaitForWindowExposed(&view));
        auto *root=view.rootObject();
        QTRY_COMPARE(root->property("count").toInt(),4);
        // Name clicks select a destination; disclosure clicks only fold the tree.
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,QPoint(100,57));
        QCOMPARE(root->property("selectedPath").toString(),QString("/root/a"));
        QCOMPARE(root->property("selections").toInt(),1);
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,QPoint(25,57));
        QTRY_COMPARE(root->property("count").toInt(),3);
        QCOMPARE(root->property("selections").toInt(),1);
        QVERIFY(QMetaObject::invokeMethod(root,"refreshFixture"));
        QTRY_COMPARE(root->property("count").toInt(),3);
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,QPoint(13,18));
        QTRY_COMPARE(root->property("count").toInt(),1);
        QCOMPARE(root->property("selectedPath").toString(),QString("/root/a"));
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,QPoint(13,18));
        QTRY_COMPARE(root->property("count").toInt(),3);
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,QPoint(25,57));
        QTRY_COMPARE(root->property("count").toInt(),4);
        QCOMPARE(root->property("selections").toInt(),1);
        // An empty folder has no disclosure action; its row still selects normally.
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,QPoint(25,135));
        QCOMPARE(root->property("selectedPath").toString(),QString("/root/b"));
        QCOMPARE(root->property("count").toInt(),4);
    }
    void liveRotationAndCropMapping() {
        QTemporaryDir temp;
        QVERIFY(QDir(temp.path()).mkdir("source"));
        const QSize size(181,321);
        QImage source(size,QImage::Format_RGB32);source.fill(Qt::red);
        QVERIFY(source.save(temp.filePath("source/photo.png")));
        const auto database=temp.filePath("state/db.sqlite");
        Backend backend(database);
        backend.addSources({temp.filePath("source")},false);
        QTRY_VERIFY_WITH_TIMEOUT(!backend.busy(),10000);
        QCOMPARE(backend.items().size(),1);
        QQuickView view;
        auto *provider=new CountingProvider(database);
        view.engine()->addImageProvider("media",provider);
        view.rootContext()->setContextProperty("backend",&backend);
        view.setSource(QUrl::fromLocalFile(QString(TEST_UI_DIR)+"/rotation_editor.qml"));
        QCOMPARE(view.status(),QQuickView::Ready);
        view.show();QVERIFY(QTest::qWaitForWindowExposed(&view));
        auto *root=view.rootObject();
        const auto asset=backend.items()[0].toMap();root->setProperty("asset",asset);
        auto *preview=root->findChild<QQuickItem*>("rotationPreview");
        auto *texture=root->findChild<QQuickItem*>("rotatedImage");
        auto *crop=root->findChild<QQuickItem*>("cropBox");
        auto *slider=root->findChild<QQuickItem*>("rotationSlider");
        auto *input=root->findChild<QQuickItem*>("angleInput");
        QVERIFY(preview&&texture&&crop&&slider&&input);
        QTRY_COMPARE_WITH_TIMEOUT(preview->property("status").toInt(),1,5000);
        QCOMPARE(provider->requests.load(),1);
        auto lastFrame=view.grabWindow();
        QVERIFY(!lastFrame.isNull());
        // Hold the mouse down and inspect intermediate angles BEFORE release.
        const auto center=slider->mapToItem(root,QPointF(slider->width()/2,slider->height()/2)).toPoint();
        QTest::mousePress(&view,Qt::LeftButton,Qt::NoModifier,center);
        for(double fraction:{.55,.65,.75,.85,.70,.60}) {
            const auto pos=slider->mapToItem(root,QPointF(slider->width()*fraction,slider->height()/2)).toPoint();
            QTest::mouseMove(&view,pos);QTest::qWait(10);
            QVERIFY(slider->property("pressed").toBool());
            QVERIFY(root->property("angle").toDouble()>0);
            QCOMPARE(texture->rotation(),root->property("angle").toDouble());
            QVERIFY(crop->isVisible());
            QCOMPARE(provider->requests.load(),1);
            const auto frame=view.grabWindow();
            QVERIFY(!frame.isNull());
            QVERIFY(frame!=lastFrame);
            lastFrame=frame;
        }
        QTest::mouseRelease(&view,Qt::LeftButton,Qt::NoModifier,center);
        // Compare actual scene coordinates to Qt's export transform, including
        // odd dimensions and integer rounding at negative/right-angle rotations.
        for(double angle:{-179.9,-90.0,-13.7,0.0,13.7,45.0,90.0,180.0,270.0,359.9}) {
            root->setProperty("angle",angle);QCoreApplication::processEvents();
            const auto transform=QImage::trueMatrix(QTransform().rotate(angle),size.width(),size.height());
            const auto scale=preview->property("fitScale").toDouble();
            const QPointF offset((preview->width()-preview->property("paintedWidth").toDouble())/2,
                                 (preview->height()-preview->property("paintedHeight").toDouble())/2);
            for(const QPointF p:{QPointF(0,0),QPointF(size.width(),0),QPointF(0,size.height()),QPointF(size.width(),size.height())}) {
                const auto displayed=texture->mapToItem(preview,QPointF(p.x()/size.width()*texture->width(),p.y()/size.height()*texture->height()));
                QVERIFY(QLineF(displayed,offset+transform.map(p)*scale).length()<.001);
            }
            for(const QPointF p:{QPointF(0,0),QPointF(crop->width(),0),QPointF(0,crop->height()),QPointF(crop->width(),crop->height())}) {
                const auto local=texture->mapFromItem(crop,p);
                QVERIFY(local.x()>=-.001&&local.y()>=-.001&&local.x()<=texture->width()+.001&&local.y()<=texture->height()+.001);
            }
        }
        QCOMPARE(provider->requests.load(),1);
        input->forceActiveFocus();
        QTest::keyClick(&view,Qt::Key_A,Qt::ControlModifier);
        for(auto key:{Qt::Key_1,Qt::Key_3,Qt::Key_Period,Qt::Key_7})QTest::keyClick(&view,key);
        QCOMPARE(root->property("angle").toDouble(),13.7);
        QCOMPARE(texture->rotation(),13.7);
        QCOMPARE(input->property("text").toString(),QString("13.7"));
        QVERIFY(QMetaObject::invokeMethod(root,"flushDraft"));
        QCOMPARE(backend.loadDraft(asset["id"].toString())[0].toMap()["angle"].toDouble(),13.7);
    }
    void continuousButtonHover() {
        QQuickView view;
        view.setSource(QUrl::fromLocalFile(QString(TEST_UI_DIR)+"/button_hover.qml"));
        QCOMPARE(view.status(),QQuickView::Ready);
        view.show();
        QVERIFY(QTest::qWaitForWindowExposed(&view));
        auto *root=view.rootObject();
        QTest::mouseMove(&view,QPoint(240,180));
        QTest::qWait(150);
        const auto idle=root->property("buttonColor").value<QColor>();
        QTest::mouseMove(&view,QPoint(15,118));
        QTest::qWait(150);
        const auto hover=root->property("buttonColor").value<QColor>();
        QVERIFY(hover!=idle);
        // Keep moving over padding, label, and the far edge, then stay still.
        for(int pass=0;pass<2;++pass) {
            for(int x=16;x<206;x+=5) {
                QTest::mouseMove(&view,QPoint(x,118));
                QTest::qWait(20);
                QCOMPARE(root->property("buttonColor").value<QColor>(),hover);
                QCOMPARE(view.cursor().shape(),Qt::PointingHandCursor);
            }
            QTest::qWait(1200);
            QCOMPARE(root->property("buttonColor").value<QColor>(),hover);
        }
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,QPoint(100,118));
        QCOMPARE(root->property("clicks").toInt(),1);
        QTest::qWait(150);
        QCOMPARE(root->property("buttonColor").value<QColor>(),hover);
        QTest::mouseMove(&view,QPoint(240,180));
        QTest::qWait(150);
        QCOMPARE(root->property("buttonColor").value<QColor>(),idle);
        root->setProperty("buttonEnabled",false);
        QTest::mouseMove(&view,QPoint(100,118));
        QTest::mouseClick(&view,Qt::LeftButton,Qt::NoModifier,QPoint(100,118));
        QCOMPARE(root->property("clicks").toInt(),1);
        QVERIFY(view.cursor().shape()!=Qt::PointingHandCursor);
    }
};

int main(int argc,char **argv) {
    qputenv("QT_QUICK_CONTROLS_STYLE","Basic");
    QGuiApplication app(argc,argv);
    UiTests tests;
    return QTest::qExec(&tests,argc,argv);
}
#include "ui_tests.moc"
