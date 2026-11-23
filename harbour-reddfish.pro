TARGET = harbour-reddfish

CONFIG += sailfishapp
QT += network

SOURCES += src/main.cpp
HEADERS += src/saver.h

DISTFILES += qml/harbour-reddfish.qml \
    qml/cover/CoverPage.qml \
    qml/pages/*.qml \
    qml/components/*.qml \
    qml/js/*.js \
    rpm/harbour-reddfish.spec \
    harbour-reddfish.desktop

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172
