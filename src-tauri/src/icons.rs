#[cfg(windows)]
mod win {
    use base64::Engine;
    use std::ffi::c_void;
    use std::mem::{size_of, zeroed};
    use std::os::windows::ffi::OsStrExt;
    use std::path::Path;

    const SIZE: usize = 32;
    const SHGFI_ICON: u32 = 0x0000_0100;
    const SHGFI_LARGEICON: u32 = 0;
    const DI_NORMAL: u32 = 0x0003;

    #[repr(C)]
    struct ShFileInfo {
        icon: isize,
        icon_index: i32,
        attributes: u32,
        display_name: [u16; 260],
        type_name: [u16; 80],
    }

    #[repr(C)]
    struct BitmapInfoHeader {
        size: u32,
        width: i32,
        height: i32,
        planes: u16,
        bit_count: u16,
        compression: u32,
        size_image: u32,
        x_pels_per_meter: i32,
        y_pels_per_meter: i32,
        colors_used: u32,
        colors_important: u32,
    }

    #[repr(C)]
    struct BitmapInfo {
        header: BitmapInfoHeader,
        color: [u8; 4],
    }

    #[link(name = "shell32")]
    extern "system" {
        fn SHGetFileInfoW(
            path: *const u16,
            attributes: u32,
            info: *mut ShFileInfo,
            size: u32,
            flags: u32,
        ) -> usize;
    }
    #[link(name = "user32")]
    extern "system" {
        fn DestroyIcon(icon: isize) -> i32;
        fn DrawIconEx(
            dc: isize,
            x: i32,
            y: i32,
            icon: isize,
            width: i32,
            height: i32,
            step: u32,
            brush: isize,
            flags: u32,
        ) -> i32;
    }
    #[link(name = "gdi32")]
    extern "system" {
        fn CreateCompatibleDC(dc: isize) -> isize;
        fn DeleteDC(dc: isize) -> i32;
        fn CreateDIBSection(
            dc: isize,
            info: *const BitmapInfo,
            usage: u32,
            bits: *mut *mut c_void,
            section: isize,
            offset: u32,
        ) -> isize;
        fn DeleteObject(object: isize) -> i32;
        fn SelectObject(dc: isize, object: isize) -> isize;
    }

    pub fn extract_icon(path: &Path) -> Option<String> {
        let wide: Vec<u16> = path.as_os_str().encode_wide().chain(Some(0)).collect();
        unsafe {
            let mut file_info: ShFileInfo = zeroed();
            if SHGetFileInfoW(
                wide.as_ptr(),
                0,
                &mut file_info,
                size_of::<ShFileInfo>() as u32,
                SHGFI_ICON | SHGFI_LARGEICON,
            ) == 0
                || file_info.icon == 0
            {
                return None;
            }
            let dc = CreateCompatibleDC(0);
            if dc == 0 {
                DestroyIcon(file_info.icon);
                return None;
            }
            let info = BitmapInfo {
                header: BitmapInfoHeader {
                    size: size_of::<BitmapInfoHeader>() as u32,
                    width: SIZE as i32,
                    height: -(SIZE as i32),
                    planes: 1,
                    bit_count: 32,
                    compression: 0,
                    size_image: 0,
                    x_pels_per_meter: 0,
                    y_pels_per_meter: 0,
                    colors_used: 0,
                    colors_important: 0,
                },
                color: [0; 4],
            };
            let mut bits: *mut c_void = std::ptr::null_mut();
            let bitmap = CreateDIBSection(dc, &info, 0, &mut bits, 0, 0);
            if bitmap == 0 || bits.is_null() {
                DeleteDC(dc);
                DestroyIcon(file_info.icon);
                return None;
            }
            let previous = SelectObject(dc, bitmap);
            let drawn = DrawIconEx(
                dc,
                0,
                0,
                file_info.icon,
                SIZE as i32,
                SIZE as i32,
                0,
                0,
                DI_NORMAL,
            ) != 0;
            let mut rgba = vec![0u8; SIZE * SIZE * 4];
            if drawn {
                let source = std::slice::from_raw_parts(bits as *const u8, rgba.len());
                let has_alpha = source.chunks_exact(4).any(|p| p[3] != 0);
                for (src, dst) in source.chunks_exact(4).zip(rgba.chunks_exact_mut(4)) {
                    dst[0] = src[2];
                    dst[1] = src[1];
                    dst[2] = src[0];
                    dst[3] = if has_alpha {
                        src[3]
                    } else if src[0] != 0 || src[1] != 0 || src[2] != 0 {
                        255
                    } else {
                        0
                    };
                }
            }
            SelectObject(dc, previous);
            DeleteObject(bitmap);
            DeleteDC(dc);
            DestroyIcon(file_info.icon);
            if !drawn {
                return None;
            }
            let mut png_bytes = Vec::new();
            {
                let mut encoder = png::Encoder::new(&mut png_bytes, SIZE as u32, SIZE as u32);
                encoder.set_color(png::ColorType::Rgba);
                encoder.set_depth(png::BitDepth::Eight);
                encoder.write_header().ok()?.write_image_data(&rgba).ok()?;
            }
            Some(format!(
                "data:image/png;base64,{}",
                base64::engine::general_purpose::STANDARD.encode(png_bytes)
            ))
        }
    }
}

#[cfg(windows)]
pub use win::extract_icon;

#[cfg(not(windows))]
pub fn extract_icon(_path: &std::path::Path) -> Option<String> {
    None
}
