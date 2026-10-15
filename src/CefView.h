// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include "include/cef_browser.h"
#include "include/cef_download_handler.h"
#include "include/cef_render_handler.h"
#include "include/cef_request_context.h"
#include <QColor>
#include <QCursor>
#include <QImage>
#include <QJSValue>
#include <QJsonObject>
#include <QMap>
#include <QMutex>
#include <QPointer>
#include <QQuickItem>
#include <QUrl>
#include <QtQml/qqmlregistration.h>
#include <functional>
#include <memory>

class CefQuickView;
class CefQuickClient;
struct CefTextureFrame;

class CefScript : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Script constants")
  public:
    enum InjectionPoint { DocumentCreation, DocumentReady };
    Q_ENUM(InjectionPoint)
    enum World { MainWorld };
    Q_ENUM(World)
};
class CefScriptCollection : public QObject {
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(QVariantList collection READ collection WRITE setCollection NOTIFY changed)
  public:
    explicit CefScriptCollection(QObject *parent) : QObject(parent) {}
    QVariantList collection() const { return scripts; }
    void setCollection(const QVariantList &value) {
        if (scripts == value)
            return;
        scripts = value;
        emit changed();
    }
  signals:
    void changed();

  private:
    QVariantList scripts;
};
class CefViewSettings : public QObject {
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(bool scrollAnimatorEnabled MEMBER scrollAnimatorEnabled NOTIFY changed)
  public:
    explicit CefViewSettings(QObject *parent) : QObject(parent) {}
    bool scrollAnimatorEnabled = true;
  signals:
    void changed();
};
class CefPermission : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Permissions are supplied by the browser")
    Q_PROPERTY(QUrl origin READ origin CONSTANT)
    Q_PROPERTY(PermissionType permissionType READ permissionType CONSTANT)
  public:
    enum class PermissionType {
        Notifications,
        ClipboardReadWrite,
        LocalFontsAccess,
        LocalNetworkAccess,
        Other
    };
    Q_ENUM(PermissionType)
    CefPermission(QUrl origin, PermissionType type, QObject *parent = nullptr);
    QUrl origin() const { return m_origin; }
    PermissionType permissionType() const { return m_type; }
    Q_INVOKABLE void grant() { accepted = true; }
    Q_INVOKABLE void deny() { accepted = false; }
    bool accepted = false;

  private:
    QUrl m_origin;
    PermissionType m_type;
};
class CefNavigationRequest : public QObject {
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(QUrl url MEMBER url CONSTANT)
    Q_PROPERTY(bool isMainFrame MEMBER isMainFrame CONSTANT)
  public:
    CefNavigationRequest(QUrl address, bool mainFrame) : url(address), isMainFrame(mainFrame) {}
    Q_INVOKABLE void reject() { rejected = true; }
    Q_INVOKABLE void accept() { rejected = false; }
    QUrl url;
    bool isMainFrame;
    bool rejected = false;
};
class CefNewWindowRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Popup requests are supplied by the browser")
    Q_PROPERTY(QUrl requestedUrl MEMBER requestedUrl CONSTANT)
    Q_PROPERTY(Destination destination MEMBER destination CONSTANT)
  public:
    enum Destination { InNewWindow, InNewTab, InNewBackgroundTab };
    Q_ENUM(Destination)
    CefNewWindowRequest(QUrl address, Destination where) : requestedUrl(address), destination(where) {}
    QUrl requestedUrl;
    Destination destination;
    CefQuickView *target = nullptr;
};
class CefNotification : public QObject {
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(QString title MEMBER m_title CONSTANT)
    Q_PROPERTY(QString message MEMBER m_message CONSTANT)
    Q_PROPERTY(QUrl origin READ origin CONSTANT)
  public:
    CefNotification(QString title, QString message, QUrl origin, QString id, CefQuickView *view);
    QUrl origin() const { return m_origin; }
    QString title() const { return m_title; }
    QString message() const { return m_message; }
    void show();
    Q_INVOKABLE void close();
    Q_INVOKABLE void click();
  signals:
    void closed();

  private:
    QString m_title, m_message, m_id;
    QUrl m_origin;
    QPointer<CefQuickView> m_view;
    bool m_closed = false;
};
class CefDownload : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Downloads are supplied by the browser")
    Q_PROPERTY(int id MEMBER id CONSTANT)
    Q_PROPERTY(QObject *view READ view CONSTANT)
    Q_PROPERTY(QUrl url MEMBER url CONSTANT)
    Q_PROPERTY(QString suggestedFileName MEMBER suggestedFileName CONSTANT)
    Q_PROPERTY(QString downloadFileName MEMBER downloadFileName NOTIFY changed)
    Q_PROPERTY(QString downloadDirectory MEMBER downloadDirectory NOTIFY changed)
    Q_PROPERTY(State state MEMBER state NOTIFY changed)
  public:
    enum State {
        DownloadRequested,
        DownloadInProgress,
        DownloadCompleted,
        DownloadCancelled,
        DownloadInterrupted
    };
    Q_ENUM(State)
    explicit CefDownload(QObject *parent) : QObject(parent) {}
    QObject *view() const;
    Q_INVOKABLE void accept();
    Q_INVOKABLE void cancel();
    int id = 0;
    QPointer<CefQuickView> source;
    QUrl url;
    QString suggestedFileName, downloadFileName, downloadDirectory;
    State state = DownloadRequested;
    bool cancelRequested = false;
    CefRefPtr<CefBeforeDownloadCallback> start;
    CefRefPtr<CefDownloadItemCallback> progress;
  signals:
    void changed();
};
class CefProfile : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString storageName MEMBER storageName)
    Q_PROPERTY(QString persistentStoragePath MEMBER persistentStoragePath)
    Q_PROPERTY(bool offTheRecord MEMBER offTheRecord)
  public:
    explicit CefProfile(QObject *parent = nullptr);
    QString storageName, persistentStoragePath;
    bool offTheRecord = false;
    CefRefPtr<CefRequestContext> context();
    Q_INVOKABLE CefPermission *queryPermission(const QUrl &origin, CefPermission::PermissionType type);
    QMap<int, QPointer<CefDownload>> downloads;
    QMap<int, CefRefPtr<CefDownloadItemCallback>> pendingDownloadCallbacks;
  signals:
    void downloadRequested(CefDownload *download);
    void downloadFinished(CefDownload *download);
    void presentNotification(CefNotification *notification);

  private:
    CefRefPtr<CefRequestContext> m_context;
    QMap<QString, CefPermission *> m_permissions;
};
class CefQuickView : public QQuickItem {
    Q_OBJECT
    QML_NAMED_ELEMENT(CefView)
    Q_PROPERTY(QUrl url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY stateChanged)
    Q_PROPERTY(int loadProgress READ loadProgress NOTIFY loadProgressChanged)
    Q_PROPERTY(LifecycleState lifecycleState READ lifecycleState WRITE setLifecycleState NOTIFY
                   lifecycleStateChanged)
    Q_PROPERTY(qint64 renderProcessPid READ renderProcessPid NOTIFY renderProcessPidChanged)
    Q_PROPERTY(CefProfile *profile READ profile WRITE setProfile NOTIFY profileChanged)
    Q_PROPERTY(
        CefQuickView *inspectedView READ inspectedView WRITE setInspectedView NOTIFY inspectedViewChanged)
    Q_PROPERTY(CefQuickView *devToolsView READ devToolsView NOTIFY devToolsViewChanged)
    Q_PROPERTY(
        QColor backgroundColor READ backgroundColor WRITE setBackgroundColor NOTIFY backgroundColorChanged)
    Q_PROPERTY(CefScriptCollection *userScripts READ userScripts CONSTANT)
    Q_PROPERTY(CefViewSettings *settings READ settings CONSTANT)
    Q_PROPERTY(QString renderingBackend READ renderingBackend NOTIFY renderingBackendChanged)
    Q_PROPERTY(bool useSystemCursor READ useSystemCursor WRITE setUseSystemCursor NOTIFY
                   useSystemCursorChanged)
    Q_PROPERTY(bool overviewPreview READ overviewPreview WRITE setOverviewPreview NOTIFY
                   overviewPreviewChanged)
  public:
    enum class LifecycleState { Active, Frozen, Discarded };
    Q_ENUM(LifecycleState)
    enum LoadStatus { LoadStartedStatus, LoadStoppedStatus, LoadSucceededStatus, LoadFailedStatus };
    Q_ENUM(LoadStatus)
    enum WebAction { Reload };
    Q_ENUM(WebAction)
    explicit CefQuickView(QQuickItem *parent = nullptr);
    ~CefQuickView() override;
    QUrl url() const { return m_url; }
    void setUrl(const QUrl &value);
    QString title() const { return m_title; }
    bool loading() const { return m_loading; }
    int loadProgress() const { return m_progress; }
    LifecycleState lifecycleState() const { return m_lifecycle; }
    void setLifecycleState(LifecycleState value);
    bool useSystemCursor() const { return m_useSystemCursor; }
    void setUseSystemCursor(bool value);
    bool overviewPreview() const { return m_overviewPreview; }
    void setOverviewPreview(bool value);
    qint64 renderProcessPid() const { return m_pid; }
    CefProfile *profile() const { return m_profile; }
    void setProfile(CefProfile *value);
    CefQuickView *inspectedView() const { return m_inspected; }
    CefQuickView *devToolsView() const { return m_devTools; }
    void setInspectedView(CefQuickView *value);
    QColor backgroundColor() const { return m_background; }
    void setBackgroundColor(const QColor &value);
    CefScriptCollection *userScripts() { return &m_scripts; }
    CefViewSettings *settings() { return &m_settings; }
    QString renderingBackend() const { return m_backend; }
    Q_INVOKABLE void runJavaScript(const QString &source, QJSValue callback = {});
    Q_INVOKABLE void triggerWebAction(WebAction action);
    Q_INVOKABLE void reload();
    Q_INVOKABLE void restoreHistoryUrl(const QUrl &url);
    Q_INVOKABLE void stop();
    Q_INVOKABLE void goBack();
    Q_INVOKABLE void goForward();
    Q_INVOKABLE void loadHtml(const QString &html, const QUrl &base = QUrl("about:blank"));
    Q_INVOKABLE void acceptAsNewWindow(CefNewWindowRequest *request);
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override;
    CefRefPtr<CefDictionaryValue> extraInfo() const;
    CefRefPtr<CefBrowser> browser() const { return m_browser; }
    void executeNotificationEvent(const QString &id, const QString &event);
  signals:
    void urlChanged();
    void titleChanged();
    void stateChanged();
    void loadStateChanged(QVariantMap info);
    void loadProgressChanged();
    void lifecycleStateChanged();
    void renderProcessPidChanged();
    void profileChanged();
    void inspectedViewChanged();
    void devToolsViewChanged();
    void backgroundColorChanged();
    void renderingBackendChanged();
    void overviewPreviewChanged();
    void useSystemCursorChanged();
    void windowCloseRequested();
    void newWindowRequested(CefNewWindowRequest *request);
    void navigationRequested(CefNavigationRequest *request);
    void permissionRequested(CefPermission *permission);

  protected:
    QSGNode *updatePaintNode(QSGNode *, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &, const QRectF &) override;
    void itemChange(ItemChange, const ItemChangeData &) override;
    void mousePressEvent(QMouseEvent *) override;
    void mouseReleaseEvent(QMouseEvent *) override;
    void mouseDoubleClickEvent(QMouseEvent *) override;
    void mouseMoveEvent(QMouseEvent *) override;
    void hoverEnterEvent(QHoverEvent *) override;
    void hoverMoveEvent(QHoverEvent *) override;
    void hoverLeaveEvent(QHoverEvent *) override;
    void wheelEvent(QWheelEvent *) override;
    void dragEnterEvent(QDragEnterEvent *) override;
    void dragMoveEvent(QDragMoveEvent *) override;
    void dragLeaveEvent(QDragLeaveEvent *) override;
    void dropEvent(QDropEvent *) override;
    void keyPressEvent(QKeyEvent *) override;
    void keyReleaseEvent(QKeyEvent *) override;
    void focusInEvent(QFocusEvent *) override;
    void focusOutEvent(QFocusEvent *) override;
    void inputMethodEvent(QInputMethodEvent *) override;

  private:
    friend class CefQuickClient;
    void ensureBrowser();
    void publishFrame(const QImage &image, bool popup = false);
    void publishAccelerated(const CefAcceleratedPaintInfo &info, bool popup);
    void syncScripts();
    void syncVisibility();
    void syncScreen();
    void syncCursor();
    void sendKey(QKeyEvent *, bool release);
    int devTools(const QString &method, const QJsonObject &params = {}, QJSValue callback = {});
    QUrl m_url;
    QString m_title;
    bool m_loading = false, m_creating = false, m_closing = false;
    int m_progress = 0;
    qint64 m_pid = 0;
    LifecycleState m_lifecycle = LifecycleState::Active;
    bool m_overviewPreview = false, m_useSystemCursor = false;
    QCursor m_webCursor;
    bool m_pointerInside = false;
    Qt::DropActions m_dropAction;
    QPointer<CefProfile> m_profile;
    QPointer<CefQuickView> m_inspected, m_devTools;
    QColor m_background = Qt::transparent;
    CefScriptCollection m_scripts;
    CefViewSettings m_settings;
    CefRefPtr<CefBrowser> m_browser;
    CefRefPtr<CefQuickClient> m_client;
    CefRefPtr<CefRegistration> m_observer;
    QMap<int, QJSValue> m_callbacks;
    QMap<int, std::function<void(QJsonObject)>> m_protocolCallbacks;
    QMap<QString, QPointer<CefNotification>> m_notifications;
    QImage m_image, m_popupImage;
    std::shared_ptr<CefTextureFrame> m_texture, m_popupTexture;
    QMutex m_frameMutex;
    QRect m_popupRect, m_imeRect;
    bool m_popupVisible = false;
    QString m_backend = QStringLiteral("Waiting for frame");
    QString m_htmlAddress, m_pendingAddress;
    QMetaObject::Connection m_screenConnection;
};
