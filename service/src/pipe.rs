//! Canal local somente para estado experimental. Não recebe credenciais nem comandos privilegiados.
use std::ffi::c_void;
use std::iter;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

const PIPE: &str = r"\\.\pipe\BlindGuardianStatus";
const INVALID_HANDLE: isize = -1;

#[repr(C)]
struct SecurityAttributes {
    length: u32,
    descriptor: *mut c_void,
    inherit: i32,
}

#[link(name = "advapi32")]
extern "system" {
    fn ConvertStringSecurityDescriptorToSecurityDescriptorW(
        text: *const u16,
        revision: u32,
        descriptor: *mut *mut c_void,
        size: *mut u32,
    ) -> i32;
}
#[link(name = "kernel32")]
extern "system" {
    fn CreateNamedPipeW(
        name: *const u16,
        open_mode: u32,
        mode: u32,
        max_instances: u32,
        out_size: u32,
        in_size: u32,
        timeout: u32,
        attributes: *const SecurityAttributes,
    ) -> isize;
    fn ConnectNamedPipe(pipe: isize, overlapped: *mut c_void) -> i32;
    fn DisconnectNamedPipe(pipe: isize) -> i32;
    fn CreateFileW(
        name: *const u16,
        access: u32,
        share: u32,
        attributes: *mut c_void,
        creation: u32,
        flags: u32,
        template: isize,
    ) -> isize;
    fn ReadFile(
        file: isize,
        buffer: *mut c_void,
        size: u32,
        read: *mut u32,
        overlapped: *mut c_void,
    ) -> i32;
    fn WriteFile(
        file: isize,
        buffer: *const c_void,
        size: u32,
        written: *mut u32,
        overlapped: *mut c_void,
    ) -> i32;
    fn FlushFileBuffers(file: isize) -> i32;
    fn CloseHandle(handle: isize) -> i32;
    fn LocalFree(memory: *mut c_void) -> *mut c_void;
    fn GetLastError() -> u32;
}

fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(iter::once(0)).collect()
}

pub fn serve(stop: Arc<AtomicBool>) -> Result<(), String> {
    // SY e BA têm controle total; usuários interativos só podem enviar/receber no canal de estado.
    let sddl = wide("D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;IU)");
    let name = wide(PIPE);
    let mut descriptor = std::ptr::null_mut();
    unsafe {
        if ConvertStringSecurityDescriptorToSecurityDescriptorW(
            sddl.as_ptr(),
            1,
            &mut descriptor,
            std::ptr::null_mut(),
        ) == 0
        {
            return Err("SDDL do pipe inválida".into());
        }
        let attrs = SecurityAttributes {
            length: std::mem::size_of::<SecurityAttributes>() as u32,
            descriptor,
            inherit: 0,
        };
        while !stop.load(Ordering::SeqCst) {
            // PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE; clientes remotos recusados.
            let pipe = CreateNamedPipeW(
                name.as_ptr(),
                0x3 | 0x0008_0000,
                0x8,
                1,
                512,
                128,
                1000,
                &attrs,
            );
            if pipe == INVALID_HANDLE {
                let code = GetLastError();
                LocalFree(descriptor);
                return Err(format!("CreateNamedPipeW: {code}"));
            }
            let connected =
                ConnectNamedPipe(pipe, std::ptr::null_mut()) != 0 || GetLastError() == 535;
            if connected {
                let mut buffer = [0u8; 32];
                let mut read = 0;
                if ReadFile(
                    pipe,
                    buffer.as_mut_ptr().cast(),
                    buffer.len() as u32,
                    &mut read,
                    std::ptr::null_mut(),
                ) != 0
                    && &buffer[..read as usize] == b"status\n"
                {
                    let response = b"experimental:unverified\n";
                    let mut written = 0;
                    let _ = WriteFile(
                        pipe,
                        response.as_ptr().cast(),
                        response.len() as u32,
                        &mut written,
                        std::ptr::null_mut(),
                    );
                    let _ = FlushFileBuffers(pipe);
                }
            }
            DisconnectNamedPipe(pipe);
            CloseHandle(pipe);
        }
        LocalFree(descriptor);
    }
    Ok(())
}

pub fn wake() {
    let name = wide(PIPE);
    unsafe {
        let handle = CreateFileW(name.as_ptr(), 0xC000_0000, 0, std::ptr::null_mut(), 3, 0, 0);
        if handle != INVALID_HANDLE {
            let mut written = 0;
            let _ = WriteFile(
                handle,
                b"stop\n".as_ptr().cast(),
                5,
                &mut written,
                std::ptr::null_mut(),
            );
            CloseHandle(handle);
        }
    }
}

pub fn query() -> Result<String, String> {
    let name = wide(PIPE);
    unsafe {
        let handle = CreateFileW(name.as_ptr(), 0xC000_0000, 0, std::ptr::null_mut(), 3, 0, 0);
        if handle == INVALID_HANDLE {
            return Err(format!("CreateFileW: {}", GetLastError()));
        }
        let mut written = 0;
        let request = b"status\n";
        let sent = WriteFile(
            handle,
            request.as_ptr().cast(),
            request.len() as u32,
            &mut written,
            std::ptr::null_mut(),
        ) != 0;
        let mut response = [0u8; 64];
        let mut read = 0;
        let received = sent
            && ReadFile(
                handle,
                response.as_mut_ptr().cast(),
                response.len() as u32,
                &mut read,
                std::ptr::null_mut(),
            ) != 0;
        CloseHandle(handle);
        if !received {
            return Err("Resposta do pipe indisponível".into());
        }
        String::from_utf8(response[..read as usize].to_vec()).map_err(|e| e.to_string())
    }
}
