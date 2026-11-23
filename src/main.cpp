#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QQmlEngine>
#include <QQmlContext>
#include <QQmlNetworkAccessManagerFactory>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QStandardPaths>
#include <QScopedPointer>

#include "saver.h"

// Pictures loaded by QML Image go through a disk cache, so they don't download again
// on the next start. (The hidden WebViews keep their own Gecko cache.)
class CachingNamFactory : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override
    {
        QNetworkAccessManager *nam = new QNetworkAccessManager(parent);
        QNetworkDiskCache *cache = new QNetworkDiskCache(nam);
        cache->setCacheDirectory(QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/images");
        cache->setMaximumCacheSize(200 * 1024 * 1024);
        nam->setCache(cache);
        return nam;
    }
};

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    // Must match [X-Sailjail] in the .desktop file (data dir, WebView profile, LocalStorage).
    app->setOrganizationName("org.reddfish");
    app->setApplicationName("harbour-reddfish");

    CachingNamFactory namFactory;
    QScopedPointer<QQuickView> view(SailfishApp::createView());
    view->engine()->setNetworkAccessManagerFactory(&namFactory);
    Saver saver;
    view->rootContext()->setContextProperty("saver", &saver);
    view->rootContext()->setContextProperty("downloadsDir",
            QStandardPaths::writableLocation(QStandardPaths::DownloadLocation));
    // Device self-test: REDDFISH_SELFTEST="url1 url2 ..." opens each page in turn, reads are logged.
    view->rootContext()->setContextProperty("selfTestUrls",
            QString::fromUtf8(qgetenv("REDDFISH_SELFTEST")));
    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    return app->exec();
}
