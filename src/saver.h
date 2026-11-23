#ifndef SAVER_H
#define SAVER_H

#include <QObject>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QStringList>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

// Saves a picture or video into ~/Pictures/Reddfish or ~/Videos/Reddfish.
// Gets a list of candidate URLs (reddit video file names vary) and keeps the first that loads.
class Saver : public QObject
{
    Q_OBJECT
public:
    explicit Saver(QObject *parent = nullptr) : QObject(parent) {}

    // video: true -> Videos folder. name: file name without folder.
    Q_INVOKABLE void save(const QStringList &urls, bool video, const QString &name)
    {
        if (urls.isEmpty()) { emit failed("nothing to save"); return; }
        tryNext(urls, 0, video, name);
    }

signals:
    void saved(const QString &path);
    void failed(const QString &error);

private:
    void tryNext(const QStringList &urls, int i, bool video, const QString &name)
    {
        QNetworkRequest req((QUrl(urls.at(i))));
        req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
        QNetworkReply *reply = m_nam.get(req);
        connect(reply, &QNetworkReply::finished, this, [=]() {
            reply->deleteLater();
            if (reply->error() != QNetworkReply::NoError) {
                if (i + 1 < urls.size()) tryNext(urls, i + 1, video, name);
                else emit failed(reply->errorString());
                return;
            }
            QString dir = QStandardPaths::writableLocation(video ? QStandardPaths::MoviesLocation
                                                                 : QStandardPaths::PicturesLocation)
                          + "/Reddfish";
            QDir().mkpath(dir);
            QFileInfo fi(name);
            QString path = dir + "/" + name;
            for (int n = 2; QFile::exists(path); ++n)      // never overwrite
                path = dir + "/" + fi.completeBaseName() + "-" + QString::number(n) + "." + fi.suffix();
            QFile f(path);
            if (!f.open(QIODevice::WriteOnly)) { emit failed(f.errorString()); return; }
            f.write(reply->readAll());
            f.close();
            emit saved(path);
        });
    }

    QNetworkAccessManager m_nam;
};

#endif
