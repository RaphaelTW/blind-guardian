use std::{ffi::c_void, iter};

#[repr(C)]
struct ServiceStatusProcess {
    service_type: u32,
    current_state: u32,
    controls_accepted: u32,
    win32_exit_code: u32,
    service_specific_exit_code: u32,
    check_point: u32,
    wait_hint: u32,
    process_id: u32,
    service_flags: u32,
}

#[link(name = "advapi32")]
extern "system" {
    fn OpenSCManagerW(machine: *const u16, database: *const u16, access: u32) -> isize;
    fn OpenServiceW(manager: isize, name: *const u16, access: u32) -> isize;
    fn QueryServiceStatusEx(
        service: isize,
        info_level: u32,
        buffer: *mut u8,
        size: u32,
        needed: *mut u32,
    ) -> i32;
    fn CloseServiceHandle(handle: isize) -> i32;
}

#[link(name = "kernel32")]
extern "system" {
    fn CreateFileW(
        name: *const u16,
        access: u32,
        share: u32,
        attributes: *mut c_void,
        creation: u32,
        flags: u32,
        template: isize,
    ) -> isize;
    fn GetNamedPipeServerProcessId(pipe: isize, process_id: *mut u32) -> i32;
    fn WriteFile(
        file: isize,
        buffer: *const c_void,
        size: u32,
        written: *mut u32,
        overlapped: *mut c_void,
    ) -> i32;
    fn ReadFile(
        file: isize,
        buffer: *mut c_void,
        size: u32,
        read: *mut u32,
        overlapped: *mut c_void,
    ) -> i32;
    fn CloseHandle(handle: isize) -> i32;
}

fn query_pipe(expected_pid: u32) -> bool {
    let name: Vec<u16> = r"\\.\pipe\BlindGuardianStatus"
        .encode_utf16()
        .chain(iter::once(0))
        .collect();
    unsafe {
        let pipe = CreateFileW(
            name.as_ptr(),
            0xC000_0000,
            0,
            std::ptr::null_mut(),
            3,
            0x0011_0000,
            0,
        );
        if pipe == -1 {
            return false;
        }
        let mut pid = 0;
        let identity_ok = GetNamedPipeServerProcessId(pipe, &mut pid) != 0 && pid == expected_pid;
        let mut written = 0;
        let sent = identity_ok
            && WriteFile(
                pipe,
                b"status\n".as_ptr().cast(),
                7,
                &mut written,
                std::ptr::null_mut(),
            ) != 0;
        let mut response = [0u8; 64];
        let mut read = 0;
        let received = sent
            && ReadFile(
                pipe,
                response.as_mut_ptr().cast(),
                response.len() as u32,
                &mut read,
                std::ptr::null_mut(),
            ) != 0;
        CloseHandle(pipe);
        received && &response[..read as usize] == b"experimental:unverified\n"
    }
}

pub fn status() -> &'static str {
    let name: Vec<u16> = "BlindGuardianService"
        .encode_utf16()
        .chain(iter::once(0))
        .collect();
    unsafe {
        let manager = OpenSCManagerW(std::ptr::null(), std::ptr::null(), 0x0001);
        if manager == 0 {
            return "SCM indisponível";
        }
        let service = OpenServiceW(manager, name.as_ptr(), 0x0004);
        if service == 0 {
            CloseServiceHandle(manager);
            return "Serviço não instalado";
        }
        let mut result = ServiceStatusProcess {
            service_type: 0,
            current_state: 0,
            controls_accepted: 0,
            win32_exit_code: 0,
            service_specific_exit_code: 0,
            check_point: 0,
            wait_hint: 0,
            process_id: 0,
            service_flags: 0,
        };
        let mut needed = 0;
        let ok = QueryServiceStatusEx(
            service,
            0,
            (&mut result as *mut ServiceStatusProcess).cast(),
            std::mem::size_of::<ServiceStatusProcess>() as u32,
            &mut needed,
        );
        CloseServiceHandle(service);
        CloseServiceHandle(manager);
        if ok == 0 {
            "Estado do serviço indisponível"
        } else if result.current_state == 4 && query_pipe(result.process_id) {
            "Serviço experimental conectado; proteção não validada"
        } else if result.current_state == 4 {
            "Serviço em execução; canal local indisponível"
        } else {
            "Serviço parado; proteção não validada"
        }
    }
}
