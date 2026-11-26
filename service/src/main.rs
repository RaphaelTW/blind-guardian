#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

#[cfg(windows)]
mod pipe;

#[cfg(windows)]
mod windows_service_host {
    use std::{
        ffi::OsString,
        sync::{
            atomic::{AtomicBool, Ordering},
            mpsc, Arc,
        },
        time::Duration,
    };
    use windows_service::{
        define_windows_service,
        service::{
            ServiceAccess, ServiceControl, ServiceControlAccept, ServiceErrorControl,
            ServiceExitCode, ServiceInfo, ServiceStartType, ServiceState, ServiceStatus,
            ServiceType,
        },
        service_control_handler::{self, ServiceControlHandlerResult},
        service_dispatcher,
        service_manager::{ServiceManager, ServiceManagerAccess},
        Error, Result,
    };

    const NAME: &str = "BlindGuardianService";
    const TYPE: ServiceType = ServiceType::OWN_PROCESS;

    define_windows_service!(ffi_service_main, service_main);

    pub fn run() -> Result<()> {
        service_dispatcher::start(NAME, ffi_service_main)
    }

    pub fn install() -> Result<()> {
        let manager = ServiceManager::local_computer(
            None::<&str>,
            ServiceManagerAccess::CONNECT | ServiceManagerAccess::CREATE_SERVICE,
        )?;
        let info = ServiceInfo {
            name: OsString::from(NAME),
            display_name: OsString::from("Blind Guardian Service"),
            service_type: TYPE,
            start_type: ServiceStartType::AutoStart,
            error_control: ServiceErrorControl::Normal,
            executable_path: std::env::current_exe().map_err(Error::Winapi)?,
            launch_arguments: vec![],
            dependencies: vec![],
            account_name: None,
            account_password: None,
        };
        let access =
            ServiceAccess::CHANGE_CONFIG | ServiceAccess::START | ServiceAccess::QUERY_STATUS;
        let service = match manager.open_service(NAME, access) {
            Ok(service) => {
                service.change_config(&info)?;
                service
            }
            Err(Error::Winapi(ref error)) if error.raw_os_error() == Some(1060) => {
                manager.create_service(&info, access)?
            }
            Err(error) => return Err(error),
        };
        if service.query_status()?.current_state != ServiceState::Running {
            service.start::<&str>(&[])?;
        }
        Ok(())
    }

    pub fn uninstall() -> Result<()> {
        let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)?;
        let access = ServiceAccess::STOP | ServiceAccess::DELETE | ServiceAccess::QUERY_STATUS;
        let service = match manager.open_service(NAME, access) {
            Ok(service) => service,
            Err(Error::Winapi(ref error)) if error.raw_os_error() == Some(1060) => return Ok(()),
            Err(error) => return Err(error),
        };
        if service.query_status()?.current_state == ServiceState::Running {
            let _ = service.stop();
        }
        service.delete()
    }

    fn service_main(_args: Vec<OsString>) {
        let _ = run_service();
    }

    fn status(state: ServiceState, accepted: ServiceControlAccept) -> ServiceStatus {
        ServiceStatus {
            service_type: TYPE,
            current_state: state,
            controls_accepted: accepted,
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::from_secs(10),
            process_id: None,
        }
    }

    fn run_service() -> Result<()> {
        let (stop_tx, stop_rx) = mpsc::channel();
        let handler = move |event| match event {
            ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
            ServiceControl::Stop => {
                let _ = stop_tx.send(());
                ServiceControlHandlerResult::NoError
            }
            _ => ServiceControlHandlerResult::NotImplemented,
        };
        let handle = service_control_handler::register(NAME, handler)?;
        let stop = Arc::new(AtomicBool::new(false));
        let pipe_stop = stop.clone();
        let worker = std::thread::spawn(move || crate::pipe::serve(pipe_stop));
        // Nenhuma política é aplicada por este esqueleto. Nunca reportar proteção ativa.
        handle.set_service_status(status(ServiceState::Running, ServiceControlAccept::STOP))?;
        let _ = stop_rx.recv();
        stop.store(true, Ordering::SeqCst);
        crate::pipe::wake();
        let _ = worker.join();
        handle.set_service_status(status(ServiceState::Stopped, ServiceControlAccept::empty()))?;
        Ok(())
    }
}

#[cfg(windows)]
fn main() -> windows_service::Result<()> {
    if std::env::args().any(|arg| arg == "--install") {
        return windows_service_host::install();
    }
    if std::env::args().any(|arg| arg == "--uninstall") {
        return windows_service_host::uninstall();
    }
    if std::env::args().any(|arg| arg == "--self-test") {
        use std::sync::{
            atomic::{AtomicBool, Ordering},
            Arc,
        };
        use std::time::Duration;
        let stop = Arc::new(AtomicBool::new(false));
        let thread_stop = stop.clone();
        let worker = std::thread::spawn(move || pipe::serve(thread_stop));
        std::thread::sleep(Duration::from_millis(250));
        let response = pipe::query().expect("Falha no canal local de estado");
        assert_eq!(response, "experimental:unverified\n");
        stop.store(true, Ordering::SeqCst);
        pipe::wake();
        worker
            .join()
            .expect("Thread do pipe falhou")
            .expect("Servidor pipe falhou");
        println!("PASS: canal local retornou estado experimental.");
        return Ok(());
    }
    windows_service_host::run()
}

#[cfg(not(windows))]
fn main() {
    eprintln!("Blind Guardian Service requer Windows.");
}
