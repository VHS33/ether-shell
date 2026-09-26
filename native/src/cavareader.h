#pragma once
// The visualiser's bars, from cava's binary output.
//
// cava sends each frame as `bars` 16-bit numbers; they're turned into
// heights from 0 to 100 here, so the shell doesn't split text 30 times a
// second.  If frames pile up, only the newest is used.
#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

class CavaReader : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(QString config READ config WRITE setConfig NOTIFY configChanged)
    Q_PROPERTY(QString program READ program WRITE setProgram NOTIFY programChanged)
    Q_PROPERTY(QStringList arguments READ arguments WRITE setArguments NOTIFY argumentsChanged)
    Q_PROPERTY(int bars READ bars WRITE setBars NOTIFY barsChanged)
    Q_PROPERTY(QList<qreal> values READ values NOTIFY valuesChanged)

public:
    explicit CavaReader(QObject *parent = nullptr);
    ~CavaReader() override;

    bool running() const { return m_want; }
    void setRunning(bool on);
    QString config() const { return m_config; }
    void setConfig(const QString &c);
    // for testing: something other than cava that writes the same frames
    QString program() const { return m_program; }
    void setProgram(const QString &p);
    QStringList arguments() const { return m_args; }
    void setArguments(const QStringList &a);
    int bars() const { return m_bars; }
    void setBars(int n);
    QList<qreal> values() const { return m_values; }

signals:
    void runningChanged();
    void configChanged();
    void programChanged();
    void argumentsChanged();
    void barsChanged();
    void valuesChanged();

private:
    void start();
    void stop();
    void onReadyRead();
    void clear();

    QProcess m_proc;
    QByteArray m_buf;
    QList<qreal> m_values;
    QString m_config;
    QString m_program = QStringLiteral("cava");
    QStringList m_args;
    int m_bars = 28;
    bool m_want = false;
};
