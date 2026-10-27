mod library;
mod lyrics;
mod player;
mod scanner;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

fn main() {
    if let Err(err) = gstreamer::init() {
        eprintln!("iMelodiae: could not initialise GStreamer: {err}");
        std::process::exit(1);
    }

    let mut app = QGuiApplication::new();
    if let Some(mut app) = app.as_mut() {
        app.as_mut().set_application_name(&QString::from("iMelodiae"));
        app.as_mut().set_organization_name(&QString::from("iMelodiae"));
    }

    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/org/imelodiae/qml/main.qml"));
    }

    let code = app.as_mut().map(|app| app.exec()).unwrap_or(1);

    // Drop the QML engine before the application object
    drop(engine);
    drop(app);
    std::process::exit(code);
}
