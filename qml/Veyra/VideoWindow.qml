// 分离画面: an independent top-level window that hosts the picture, so a second
// monitor can show it while the main window stays on the parameters.
//
// There is no second renderer here. apps/veyra-qml/main.cpp moves the one native
// D3D12 video window (and its swapchain) under this window while it is shown, and
// places it over the item named "detachedVideoHost", exactly as it does with the
// main window's "videoHost". The presenter follows the window to its monitor
// (refresh rate, HDR peak, VRR) through its existing display-change path.
//
// The window has a native frame so it can be moved between monitors, maximized
// and resized with the system's own handles. It has no transient parent: it gets
// its own taskbar button, can go fullscreen on its own screen and is not kept
// above the main window. Closing it puts the picture back into the main window.
import QtQuick
import QtQuick.Window
import QtCore

Window {
    id: win
    objectName: "videoWindow"
    required property Window owner
    // Emitted when the user closes this window: the owner docks the picture.
    signal dockRequested()
    transientParent: null
    flags: Qt.Window
    title: qsTr("Veyra 画面")
    color: Theme.videoBlack
    width: 1280; height: 720
    minimumWidth: 320; minimumHeight: 180

    readonly property bool fullscreen: visibility === Window.FullScreen
    // False while the main window has the picture back (another page, or its own
    // fullscreen); this window then says where the picture went.
    property bool pictureHere: true
    // Read by main.cpp for the native video window, as the main window's is.
    property bool cursorIdle: false
    readonly property bool fullscreenCursorHidden: fullscreen && cursorIdle
    property int restoreVisibility: Window.Windowed

    function toggleFullscreen() {
        if (!fullscreen) {
            restoreVisibility = visibility === Window.Maximized ? Window.Maximized : Window.Windowed
            visibility = Window.FullScreen
        } else {
            visibility = restoreVisibility
        }
        veyra.logUi("ui-video-window", "fullscreen=" + (visibility === Window.FullScreen))
    }

    // Remembered per profile, next to the other window files in the data directory.
    Settings {
        id: saved
        location: {
            const path = veyra.dataDirectory.replace(/\\/g, '/')
            const encoded = path.split('/').map(encodeURIComponent).join('/')
            const directory = path.startsWith('//') ? "file:" + encoded
                : "file:///" + encoded.replace(/^([A-Za-z])%3A/, '$1:')
            return directory + "/video-window.ini"
        }
        property int x: -1
        property int y: -1
        property int width: 0
        property int height: 0
        property bool maximized: false
        property bool detached: false
    }
    readonly property bool restoreDetached: saved.detached

    // The saved rectangle only counts while its centre is still on a connected
    // screen; a monitor that has been unplugged must not hold the picture.
    function savedRectOnScreen() {
        if (saved.width < minimumWidth || saved.height < minimumHeight) return false
        const cx = saved.x + saved.width / 2, cy = saved.y + saved.height / 2
        const screens = Qt.application.screens
        for (let i = 0; i < screens.length; ++i) {
            const s = screens[i]
            if (cx >= s.virtualX && cx < s.virtualX + s.width && cy >= s.virtualY && cy < s.virtualY + s.height)
                return true
        }
        return false
    }
    // First use: the screen the main window is not on, if there is one.
    function placeDefault() {
        const screens = Qt.application.screens
        let target = null
        for (let i = 0; i < screens.length && !target; ++i)
            if (!owner.screen || screens[i].name !== owner.screen.name) target = screens[i]
        if (!target) target = owner.screen
        if (!target) return
        width = Math.max(minimumWidth, Math.min(1280, target.width - 80))
        height = Math.max(minimumHeight, Math.round(width * 9 / 16))
        if (height > target.height - 80) { height = target.height - 80; width = Math.round(height * 16 / 9) }
        x = target.virtualX + Math.round((target.width - width) / 2)
        y = target.virtualY + Math.round((target.height - height) / 2)
    }
    function open() {
        if (!visible) {
            if (savedRectOnScreen()) {
                x = saved.x; y = saved.y; width = saved.width; height = saved.height
            } else {
                placeDefault()
            }
            visibility = saved.maximized && savedRectOnScreen() ? Window.Maximized : Window.Windowed
        }
        raise()
        saved.detached = true
        veyra.logUi("ui-video-window", "shown at " + x + "," + y + " " + width + "x" + height)
    }
    function remember() {
        if (!visible) return
        saved.maximized = visibility === Window.Maximized
        if (visibility === Window.Windowed) {
            saved.x = x; saved.y = y; saved.width = width; saved.height = height
        }
    }
    // Called by the owner: keep the geometry, forget the detached state. Not named
    // close(), which would shadow QWindow::close().
    function dock() {
        if (!visible) return
        remember()
        saved.detached = false
        if (fullscreen) visibility = restoreVisibility
        hide()
        veyra.logUi("ui-video-window", "hidden")
    }
    onClosing: event => { event.accepted = false; win.dockRequested() }
    // The owner closing ends the application: keep 已分离 for the next start.
    Connections {
        target: win.owner
        function onClosing(event) { if (win.visible) win.remember() }
    }

    // The native video window draws over this; it shows while no picture is up.
    Item {
        id: detachedVideoHost
        objectName: "detachedVideoHost"
        anchors.fill: parent
    }
    Text {
        anchors.centerIn: parent
        visible: !veyra.hasSource || !win.pictureHere
        text: !win.pictureHere ? qsTr("画面暂时回到主窗口 · 返回专业模式后显示在这里")
            : veyra.openingSource ? qsTr("正在连接…") : qsTr("没有画面 · 在主窗口打开片源")
        color: Theme.t3
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsH3
    }

    // The native picture passes the pointer through (HTTRANSPARENT), so these see it.
    TapHandler {
        onDoubleTapped: win.toggleFullscreen()
    }
    HoverHandler {
        cursorShape: win.fullscreenCursorHidden ? Qt.BlankCursor : Qt.ArrowCursor
        property point last: Qt.point(-1, -1)
        onPointChanged: {
            const p = point.position
            if (Math.abs(p.x - last.x) < 1 && Math.abs(p.y - last.y) < 1) return
            last = p
            win.cursorIdle = false
            idle.restart()
        }
    }
    Timer { id: idle; interval: 1600; onTriggered: win.cursorIdle = true }

    // The main window's shortcuts belong to that window; the basics work here too.
    Shortcut { sequences: ["F11", "Alt+Return", "Alt+Enter"]; onActivated: win.toggleFullscreen() }
    Shortcut { sequence: "Esc"; enabled: win.fullscreen; onActivated: win.toggleFullscreen() }
    Shortcut { sequence: veyra.shortcuts.playPause; onActivated: veyra.togglePlayPause() }
    Shortcut { sequence: "Left"; onActivated: veyra.seekBy(-5) }
    Shortcut { sequence: "Right"; onActivated: veyra.seekBy(5) }
}
