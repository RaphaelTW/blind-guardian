import { invoke } from '@tauri-apps/api/core';

export type ProtectionState = 'unprotected' | 'pending_validation' | 'active' | 'temporarily_authorized' | 'unsupported' | 'failed';
export interface InstalledApp {
  id: string;
  name: string;
  version: string;
  publisher: string;
  executable: string | null;
  icon: string | null;
}
export interface ProtectionRecord {
  appId: string;
  name: string;
  executable: string;
  state: ProtectionState;
  strategy: string;
  detail: string;
}

export const api = {
  initialized: () => invoke<boolean>('is_initialized'),
  initialize: (password: string) => invoke<void>('initialize_admin', { password }),
  login: (username: string, password: string) => invoke<string>('login', { username, password }),
  logout: () => invoke<void>('logout'),
  changeCredentials: (token: string, currentUsername: string, currentPassword: string, newUsername: string, newPassword: string) =>
    invoke<void>('change_credentials', { token, currentUsername, currentPassword, newUsername, newPassword }),
  apps: (token: string) => invoke<InstalledApp[]>('list_installed', { token }),
  protections: (token: string) => invoke<ProtectionRecord[]>('list_protection', { token }),
  addManual: (token: string, path: string) => invoke<InstalledApp>('add_manual', { token, path }),
  request: (token: string, username: string, password: string, appId: string) =>
    invoke<ProtectionRecord>('request_protection', { token, username, password, appId }),
  remove: (token: string, username: string, password: string, appId: string) =>
    invoke<void>('remove_protection_request', { token, username, password, appId }),
  authorize: (appId: string, password: string) => invoke<void>('authorize_execution', { appId, password }),
  launchRequest: () => invoke<ProtectionRecord | null>('launch_request'),
  launchManaged: (appId: string, password: string) => invoke<void>('launch_managed', { appId, password }),
  createManagedShortcut: (token: string, appId: string) => invoke<void>('create_managed_shortcut', { token, appId }),
  serviceStatus: () => invoke<string>('service_status'),
  quit: (username: string, password: string, confirmed: boolean) =>
    invoke<void>('quit_authenticated', { username, password, confirmed }),
};
