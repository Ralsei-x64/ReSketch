// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <source_location>

void checkExtensions(AppSettings &settings, QQuickWindow *window, bool checkUi = true) {
    window->show();
    settings.setWindowControlsInTabBar(true);
    settings.setKeepWindowDecorations(false);
    CefProfile profile; profile.persistentStoragePath = settings.profileStoragePath();
    CefQuickView extensionView; extensionView.setProfile(&profile); extensionView.setSize(QSizeF(400,300));
    auto *view = &extensionView;
    auto *extensions = settings.extensions();
    const auto until = [extensions, window](auto predicate, std::source_location location = std::source_location::current()) {
        QElapsedTimer time; time.start();
        while (!predicate() && time.elapsed() < 15000) QTest::qWait(10);
        if (!predicate()) fprintf(stderr,"Extension wait failed at line %u: %s / %s\n",location.line(),qPrintable(extensions->error()),QJsonDocument::fromVariant(extensions->extensions()).toJson().constData());
        assert(predicate());
    };
    const auto fixture = qEnvironmentVariable("RESKETCH_TEST_CRX_DIR");
    assert(!fixture.isEmpty());
    for (const auto &name : {"traversal.crx","absolute.crx","backslash.crx","symlink.crx","old-manifest.crx","bad-header.crx","bomb.crx"}) {
        assert(!extensions->installPackage(fixture+'/'+name));
        assert(extensions->extensions().isEmpty());
    }
    assert(extensions->installPackage(fixture+"/valid.crx"));
    assert(!extensions->installPackage(fixture+"/valid.crx"));
    const auto key=extensions->extensions().first().toMap().value("key").toString();
    assert(extensions->extensions().first().toMap().value("name")=="Local extension fixture");
    {
        // Simulate an older install that persisted the untranslated manifest token.
        QSettings stored;
        auto entries = stored.value("extensions/packages").toList();
        auto row = entries.first().toMap(); row["name"] = "__MSG_extName__"; entries[0] = row;
        stored.setValue("extensions/packages", entries);
        ExtensionManager restored(nullptr, false);
        assert(restored.extensions().first().toMap().value("name")=="Local extension fixture");
    }
    fprintf(stderr,"Waiting for custom extension load\n");
    until([&]{return extensions->extensions().first().toMap().value("loaded").toBool();});
    assert(extensions->extensionPage(key,false).scheme()=="chrome-extension");
    assert(extensions->extensionPage(key,true).path()=="/options.html");
    // Exercise Chromium's extension engine against an HTTP fixture, without Figma or any account.
    QTcpServer page;
    assert(page.listen(QHostAddress::LocalHost));
    QObject::connect(&page,&QTcpServer::newConnection,&page,[&]{while(auto *socket=page.nextPendingConnection()){
        QObject::connect(socket,&QTcpSocket::readyRead,socket,[socket]{socket->readAll();socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n<title>Extension content fixture</title><p>Local fixture</p>");socket->disconnectFromHost();});
        QObject::connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
    }});
    fprintf(stderr,"Checking real content script\n");
    view->setUrl(QUrl(QString("http://127.0.0.1:%1/").arg(page.serverPort())));
    until([&]{return view->title()=="Extension content fixture";});
    QJsonObject value; bool finished=false;
    until([&] {
        finished=false;
        view->runDevTools("Runtime.evaluate",{{"expression","document.documentElement.dataset.extensionFixture"},{"returnByValue",true}},[&](bool ok,QJsonObject result){assert(ok);value=result;finished=true;});
        until([&]{return finished;});
        return value.value("result").toObject().value("value")=="loaded";
    });
    // The extension UI is a real chrome-extension page, including its runtime API.
    fprintf(stderr,"Checking real popup page\n");
    view->setUrl(extensions->extensionPage(key,false));
    until([&]{return view->title()=="Extension popup";});
    finished=false;
    view->runDevTools("Runtime.evaluate",{{"expression","chrome.runtime.id"},{"returnByValue",true}},[&](bool ok,QJsonObject result){assert(ok);value=result;finished=true;});
    until([&]{return finished;});
    assert(!value.value("result").toObject().value("value").toString().isEmpty());
    finished=false;
    view->runDevTools("Runtime.evaluate",{{"expression","chrome.storage.local.set({retained:'yes'}).then(()=>true)"},{"awaitPromise",true},{"returnByValue",true}},[&](bool ok,QJsonObject result){assert(ok&&!result.contains("exceptionDetails"));finished=true;});
    until([&]{return finished;});
    extensions->setExtensionEnabled(key,false);
    until([&]{return !extensions->extensions().first().toMap().value("loaded").toBool();});
    assert(extensions->extensionPage(key,false).isEmpty());
    extensions->setExtensionEnabled(key,true);
    until([&]{return extensions->extensions().first().toMap().value("loaded").toBool();});
    view->setUrl(QUrl("about:blank"));
    view->setUrl(extensions->extensionPage(key,false));
    until([&]{return view->title()=="Extension popup";});
    finished=false;
    view->runDevTools("Runtime.evaluate",{{"expression","chrome.storage.local.get('retained').then(value=>value.retained)"},{"awaitPromise",true},{"returnByValue",true}},[&](bool ok,QJsonObject result){assert(ok);value=result;finished=true;});
    until([&]{return finished;});
    assert(value.value("result").toObject().value("value")=="yes");
    // A malformed package must not block custom extension management.
    assert(extensions->installPackage(fixture+"/broken-script.crx"));
    until([&]{return !extensions->extensions().last().toMap().value("error").toString().isEmpty();});
    // Idle extension management must not retain a hidden Chrome WebUI renderer.
    until([&]{
        finished=false;
        view->runDevTools("Target.getTargets",{},[&](bool ok,QJsonObject result){assert(ok);value=result;finished=true;});
        until([&]{return finished;});
        for(const auto &target:value.value("targetInfos").toArray())if(target.toObject().value("url")=="chrome://extensions/")return false;
        return true;
    });
    if (!checkUi) {
        puts("Chromium extension loading, local storage, toggles and failure isolation passed");
        return;
    }
    fprintf(stderr,"Checking toolbar extension controls\n");
    const auto findVisual = [](auto self, QQuickItem *item, const QString &name) -> QQuickItem * {
        if (item->objectName()==name) return item;
        for (auto *child:item->childItems()) if (auto *found=self(self,child,name)) return found;
        return nullptr;
    };
    auto *button = findVisual(findVisual,window->contentItem(),"toolbarButton-extensions");
    auto *menu = window->findChild<QObject *>("extensionsMenu");
    assert(button && menu);
    assert(QMetaObject::invokeMethod(window,"triggerToolbarItem",Q_ARG(QVariant,"extensions"),Q_ARG(QVariant,QVariant::fromValue<QObject *>(button))));
    until([&]{return menu->property("visible").toBool();});
    QMetaObject::invokeMethod(menu,"close");
    assert(QMetaObject::invokeMethod(menu,"showExtension",Q_ARG(QVariant,key),Q_ARG(QVariant,false)));
    until([&]{auto *popup=window->findChild<CefQuickView *>("toolbarExtensionView");return popup&&popup->title()=="Extension popup";});
    auto *popup = window->findChild<QObject *>("extensionToolbarPopup");
    assert(popup && popup->property("visible").toBool());
    auto *popupView = window->findChild<CefQuickView *>("toolbarExtensionView");
    const auto externalUrl = QString("http://127.0.0.1:%1/external").arg(page.serverPort());
    const auto externalWindow = [&]() -> QQuickWindow * {
        const auto windows = window->findChildren<QQuickWindow *>("extensionWindow");
        return windows.isEmpty() ? nullptr : windows.last();
    };
    fprintf(stderr,"Checking extension external windows\n");
    // window.open must preserve its opener and render outside the toolbar popup.
    popupView->runJavaScript("window.child=window.open('" + externalUrl + "')");
    until([&]{auto *w=externalWindow();return w&&w->findChild<CefQuickView *>("extensionWindowView")->title()=="Extension content fixture";});
    auto *external = externalWindow();
    assert(external->flags().testFlag(Qt::FramelessWindowHint));
    assert(external->findChild<QQuickItem *>("externalWindowHeader"));
    finished=false;
    external->findChild<CefQuickView *>("extensionWindowView")->runDevTools("Runtime.evaluate",{{"expression","opener !== null"},{"returnByValue",true}},[&](bool ok,QJsonObject result){assert(ok&&result.value("result").toObject().value("value").toBool());finished=true;});
    until([&]{return finished;});
    external->close(); until([&]{return externalWindow()==nullptr;});
    // Same-window links are redirected out of the toolbar popup as well.
    popupView->runJavaScript("location.href='" + externalUrl + "'");
    until([&]{auto *w=externalWindow();return w&&w->findChild<CefQuickView *>("extensionWindowView")->title()=="Extension content fixture";});
    assert(popupView->url().scheme()=="chrome-extension");
    externalWindow()->close(); until([&]{return externalWindow()==nullptr;});
    fprintf(stderr,"Checking chrome.tabs.create\n");
    // Extension APIs are also used by real extensions to open sites and settings.
    popupView->runJavaScript("chrome.tabs.create({url:'" + externalUrl + "'})");
    until([&]{auto *w=externalWindow();return w&&w->findChild<CefQuickView *>("extensionWindowView")->title()=="Extension content fixture";});
    externalWindow()->close(); until([&]{return externalWindow()==nullptr;});
    popupView->runJavaScript("chrome.runtime.openOptionsPage()");
    until([&]{auto *w=externalWindow();return w&&w->findChild<CefQuickView *>("extensionWindowView")->title()=="Extension options";});
    externalWindow()->close(); until([&]{return externalWindow()==nullptr;});
    QMetaObject::invokeMethod(popup,"close");
    assert(QMetaObject::invokeMethod(menu,"showExtension",Q_ARG(QVariant,key),Q_ARG(QVariant,true)));
    until([&]{auto *w=externalWindow();return w&&w->findChild<CefQuickView *>("extensionWindowView")->title()=="Extension options";});
    extensions->setExtensionEnabled(key,false);
    until([&]{return externalWindow()==nullptr;});
    extensions->setExtensionEnabled(key,true);
    until([&]{return extensions->extensions().first().toMap().value("loaded").toBool();});
    fprintf(stderr,"Checking extension settings layout\n");
    assert(QMetaObject::invokeMethod(window,"openExtensionSettings"));
    until([&]{return window->findChild<QQuickItem *>("loadCrxExtension") != nullptr;});
    auto *load = window->findChild<QQuickItem *>("loadCrxExtension");
    auto *settingsWindow = load->window();
    assert(settingsWindow && settingsWindow->property("selectedSection").toInt()==8);
    for (const auto size : {QSize(650,420), QSize(880,700)}) {
        settingsWindow->resize(size); QTest::qWait(100);
        auto *name = findVisual(findVisual, settingsWindow->contentItem(), "extensionName-"+key);
        auto *card = findVisual(findVisual, settingsWindow->contentItem(), "extensionCard-"+key);
        if (!name || !card) fprintf(stderr,"Missing extension settings name/card: %p %p\n",(void*)name,(void*)card);
        assert(name && card && name->property("text")=="Local extension fixture");
        assert(name->width()>0 && card->width()<settingsWindow->width()-164);
        for (const auto &prefix : {"extensionEnabled-", "extensionPopup-", "extensionOptions-", "extensionRemove-"}) {
            auto *control = findVisual(findVisual, settingsWindow->contentItem(), QString(prefix)+key);
            assert(control && control->isEnabled() && control->isVisible());
            const auto origin = control->mapToItem(card, QPointF());
            assert(origin.x()>=0 && origin.x()+control->width()<=card->width()+1);
            assert(origin.y()>=0 && origin.y()+control->height()<=card->height()+1);
        }
    }
    auto *optionButton = findVisual(findVisual, settingsWindow->contentItem(), "extensionOptions-"+key);
    assert(QMetaObject::invokeMethod(optionButton,"clicked"));
    until([&]{auto *w=externalWindow();return w&&w->findChild<CefQuickView *>("extensionWindowView")->title()=="Extension options";});
    externalWindow()->close(); until([&]{return externalWindow()==nullptr;});
    const auto screenshot = qEnvironmentVariable("RESKETCH_EXTENSIONS_SCREENSHOT");
    if (!screenshot.isEmpty()) assert(settingsWindow->grabWindow().save(screenshot));
    auto *enabled = findVisual(findVisual, settingsWindow->contentItem(), "extensionEnabled-"+key);
    enabled->setProperty("checked", false);
    assert(QMetaObject::invokeMethod(enabled,"toggled"));
    until([&]{return !extensions->extensions().first().toMap().value("enabled").toBool() && !extensions->extensions().first().toMap().value("loaded").toBool();});
    enabled = findVisual(findVisual, settingsWindow->contentItem(), "extensionEnabled-"+key);
    enabled->setProperty("checked", true);
    assert(QMetaObject::invokeMethod(enabled,"toggled"));
    until([&]{return extensions->extensions().first().toMap().value("loaded").toBool();});
    auto *remove = findVisual(findVisual, settingsWindow->contentItem(), "extensionRemove-"+key);
    assert(remove && QMetaObject::invokeMethod(remove,"clicked"));
    assert(extensions->extensions().size()==1);
    puts("CRX limits, archive traversal protection, real Chromium content scripts, popup APIs, toggles and failure isolation passed");
}
