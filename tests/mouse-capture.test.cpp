// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "CefMouseCapture.h"
#include <QGuiApplication>
#include <QCursor>
#include <QMouseEvent>
#include <QProcess>
#include <QQuickWindow>
#include <QTest>
#include <QtGui/qguiapplication_platform.h>
#include <wayland-client.h>
#include "fake-input-client.h"
#include <cstring>
#include <cstdio>
#include <stdexcept>

int main(int argc, char **argv) {
    QGuiApplication app(argc,argv);
    const auto require=[](bool ok,const char *message){if(!ok)throw std::runtime_error(message);};
    const auto until=[&](auto condition,const char *message){for(int i=0;i<300&&!condition();++i)QTest::qWait(10);require(condition(),message);};
    struct Window:QQuickWindow {
        CefMouseCapture *capture=nullptr;
        bool event(QEvent *event) override {
            if(event->type()==QEvent::MouseMove&&capture&&capture->move(static_cast<QMouseEvent *>(event)))return true;
            return QQuickWindow::event(event);
        }
    } window;
    CefMouseCapture capture(&window);window.capture=&capture;
    wl_display *display=nullptr;wl_registry *registry=nullptr;org_kde_kwin_fake_input *fake=nullptr;
    if(auto *native=qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>()) {
        display=native->display();registry=wl_display_get_registry(display);
        static const wl_registry_listener listener={[](void *data,wl_registry *registry,uint32_t name,const char *interface,uint32_t version){
            if(!strcmp(interface,"org_kde_kwin_fake_input"))*static_cast<org_kde_kwin_fake_input **>(data)=static_cast<org_kde_kwin_fake_input *>(wl_registry_bind(registry,name,&org_kde_kwin_fake_input_interface,qMin(version,3U)));
        },[](void *,wl_registry *,uint32_t){}};
        wl_registry_add_listener(registry,&listener,&fake);wl_display_flush(display);
        until([&]{return fake;},"Isolated compositor exposes test input");
        org_kde_kwin_fake_input_authenticate(fake,"ReSketch test","Isolated pointer capture test");
    }
    window.setColor(Qt::white);window.resize(800,600);window.showMaximized();window.requestActivate();
    until([&]{return window.isActive()&&window.isExposed();},"Test window active");
    if(fake) {
        org_kde_kwin_fake_input_pointer_motion_absolute(fake,wl_fixed_from_int(300),wl_fixed_from_int(300));
        org_kde_kwin_fake_input_button(fake,0x110,1);wl_display_flush(display);
    } else require(QProcess::execute("xdotool",{"mousemove","300","300","mousedown","1"})==0,"X11 test input");
    QTest::qWait(150);
    QPointF total;bool lost=false;
    require(capture.start(&window,[&](QPointF delta){total+=delta;},[&]{lost=true;}),"Native capture starts");
    QTest::qWait(150);
    for(int i=0;i<20;++i) {
        const auto previous=total.x();
        if(fake){org_kde_kwin_fake_input_pointer_motion(fake,wl_fixed_from_int(1000),0);wl_display_flush(display);}
        else QCursor::setPos(QCursor::pos()+QPoint(60,0));
        until([&]{return total.x()>previous;},"Relative motion arrives");
    }
    require(total.x()>(fake?19000:1100),"Motion continues beyond the output edge");
    require(!lost,"Capture stays active during continuous movement");
    capture.stop();window.unsetCursor();
    const auto stopped=total;
    if(fake){org_kde_kwin_fake_input_button(fake,0x110,0);org_kde_kwin_fake_input_pointer_motion(fake,wl_fixed_from_int(10),0);wl_display_flush(display);}
    else require(QProcess::execute("xdotool",{"mouseup","1"})==0,"Release X11 input");
    QTest::qWait(100);require(total==stopped,"Stopped capture emits no motion");
    require(capture.start(&window,[](QPointF){},[&]{lost=true;}),"Capture can restart");
    window.hide();until([&]{return lost;},"Hiding the window releases capture");
    capture.stop();
    if(fake)org_kde_kwin_fake_input_destroy(fake);
    if(registry)wl_registry_destroy(registry);
    fprintf(stderr,"%s continuous motion beyond screen bounds, stop/restart and hidden-window release passed\n",qPrintable(QGuiApplication::platformName()));
}
