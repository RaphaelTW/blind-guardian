import { useEffect, useMemo, useRef, useState } from 'react';
import { listen } from '@tauri-apps/api/event';
import { openUrl } from '@tauri-apps/plugin-opener';
import { api, type InstalledApp, type ProtectionRecord, type ProtectionState } from './api';

type Modal = { kind: 'protect' | 'remove' | 'launch'; appId: string; name: string } | { kind: 'quit' } | null;
const labels: Record<ProtectionState, string> = {
  unprotected: 'Não protegido',
  pending_validation: 'Aguardando validação',
  active: 'Proteção ativa',
  temporarily_authorized: 'Temporariamente autorizado',
  unsupported: 'Não suportado',
  failed: 'Falha na proteção',
};

function Shield({ size = 28 }: { size?: number }) {
  return <svg width={size} height={size} viewBox="0 0 48 48" aria-hidden="true" fill="none">
    <path d="M24 3 41 10v13c0 11-6.8 18.2-17 22C13.8 41.2 7 34 7 23V10L24 3Z" fill="currentColor" opacity=".15" />
    <path d="M24 3 41 10v13c0 11-6.8 18.2-17 22C13.8 41.2 7 34 7 23V10L24 3Z" stroke="currentColor" strokeWidth="3" strokeLinejoin="round" />
    <path d="m17 24 5 5 10-11" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
  </svg>;
}

function PasswordField({ value, onChange, id = 'password', inputRef }: { value: string; onChange: (value: string) => void; id?: string; inputRef?: React.Ref<HTMLInputElement> }) {
  const [visible, setVisible] = useState(false);
  return <div className="input-group">
    <input ref={inputRef} id={id} className="form-control" type={visible ? 'text' : 'password'} autoComplete="current-password" value={value} onChange={e => onChange(e.target.value)} required />
    <button className="btn btn-outline-secondary" type="button" aria-label={visible ? 'Ocultar senha' : 'Mostrar senha'} onClick={() => setVisible(v => !v)}><i className={`bi bi-eye${visible ? '-slash' : ''}`} /></button>
  </div>;
}

function AppIcon({ app }: { app: InstalledApp }) {
  return app.icon ? <img className="app-icon" src={app.icon} alt="" /> : <span className="app-icon fallback-icon"><i className="bi bi-app" /></span>;
}

function ErrorLine({ error }: { error: string }) { return error ? <div className="alert alert-danger py-2" role="alert">{error}</div> : null; }

function SettingsDialog({ token, service, onClose, onChanged }: { token: string; service: string; onClose: () => void; onChanged: () => void }) {
  const [currentUser, setCurrentUser] = useState('rakdos');
  const [currentPassword, setCurrentPassword] = useState('');
  const [newUser, setNewUser] = useState('rakdos');
  const [newPassword, setNewPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  async function save(e: React.FormEvent) {
    e.preventDefault(); setBusy(true); setError('');
    try { await api.changeCredentials(token, currentUser, currentPassword, newUser, newPassword); onChanged(); }
    catch (e) { setError(String(e)); } finally { setBusy(false); }
  }
  return <div className="modal-backdrop-custom"><section className="auth-modal" role="dialog" aria-modal="true" aria-labelledby="settings-title" onKeyDown={e => { if (e.key === 'Escape') onClose(); }}><div className="modal-top"><div className="modal-symbol"><i className="bi bi-gear" /></div><button className="close-button" aria-label="Fechar" onClick={onClose}><i className="bi bi-x-lg" /></button></div><h2 id="settings-title">Configurações</h2><p className="text-secondary">{service}<br />Blind Guardian 0.1.0-alpha · Raphael Laurentino</p><form onSubmit={save}><label className="form-label" htmlFor="current-user">Username atual</label><input id="current-user" className="form-control mb-3" value={currentUser} onChange={e => setCurrentUser(e.target.value)} required /><label className="form-label" htmlFor="current-password">Senha atual</label><PasswordField id="current-password" value={currentPassword} onChange={setCurrentPassword} /><label className="form-label mt-3" htmlFor="new-user">Novo username</label><input id="new-user" className="form-control mb-3" value={newUser} onChange={e => setNewUser(e.target.value)} required /><label className="form-label" htmlFor="new-password">Nova senha</label><PasswordField id="new-password" value={newPassword} onChange={setNewPassword} /><small className="text-secondary">Mínimo de 12 caracteres.</small><div className="mt-3"><ErrorLine error={error} /></div><div className="modal-buttons"><button type="button" className="btn btn-outline-secondary" onClick={onClose}>Cancelar</button><button className="btn btn-primary" disabled={busy}>{busy ? 'Aguarde…' : 'Salvar'}</button></div></form></section></div>;
}

export default function App() {
  const [initialized, setInitialized] = useState<boolean | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [username, setUsername] = useState('rakdos');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [tab, setTab] = useState<'installed' | 'protected'>('installed');
  const [apps, setApps] = useState<InstalledApp[]>([]);
  const [records, setRecords] = useState<ProtectionRecord[]>([]);
  const [query, setQuery] = useState('');
  const [manualPath, setManualPath] = useState('');
  const [modal, setModal] = useState<Modal>(null);
  const [modalUser, setModalUser] = useState('rakdos');
  const [modalPassword, setModalPassword] = useState('');
  const [modalError, setModalError] = useState('');
  const [quitConfirmed, setQuitConfirmed] = useState(false);
  const [service, setService] = useState('Verificando serviço…');
  const [quitRequested, setQuitRequested] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const firstInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const theme = matchMedia('(prefers-color-scheme: dark)');
    const sync = () => { document.documentElement.dataset.bsTheme = theme.matches ? 'dark' : 'light'; };
    sync(); theme.addEventListener('change', sync);
    void api.initialized().then(setInitialized).catch(e => setError(String(e)));
    void api.serviceStatus().then(setService).catch(() => setService('Serviço indisponível'));
    let unlistenClose: (() => void) | undefined;
    let unlistenQuit: (() => void) | undefined;
    void listen('session-closed', () => { setToken(null); setPassword(''); setModal(null); }).then(fn => { unlistenClose = fn; });
    void listen('quit-requested', () => { setQuitRequested(true); setModal({ kind: 'quit' }); }).then(fn => { unlistenQuit = fn; });
    return () => { theme.removeEventListener('change', sync); unlistenClose?.(); unlistenQuit?.(); };
  }, []);

  useEffect(() => {
    if (modal) {
      setModalPassword(''); setModalError(''); setQuitConfirmed(false);
      setTimeout(() => firstInput.current?.focus(), 0);
    }
  }, [modal]);

  async function refresh(currentToken: string) {
    const [found, protectedApps] = await Promise.all([api.apps(currentToken), api.protections(currentToken)]);
    setApps(found); setRecords(protectedApps);
  }

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault(); setBusy(true); setError('');
    try {
      if (!initialized) {
        if (password !== confirmPassword) throw new Error('As senhas não coincidem.');
        await api.initialize(password); setInitialized(true); setConfirmPassword('');
      }
      const value = await api.login(username, password);
      setToken(value); setPassword(''); await refresh(value);
      if (quitRequested) setModal({ kind: 'quit' });
    } catch (e) { setError(String(e)); } finally { setBusy(false); }
  }

  async function runModal(e: React.FormEvent) {
    e.preventDefault(); if (!modal) return;
    setBusy(true); setModalError('');
    try {
      if (modal.kind === 'quit') {
        await api.quit(modalUser, modalPassword, quitConfirmed);
      } else if (modal.kind === 'launch') {
        await api.authorize(modal.appId, modalPassword);
      } else if (token) {
        if (modal.kind === 'protect') await api.request(token, modalUser, modalPassword, modal.appId);
        else await api.remove(token, modalUser, modalPassword, modal.appId);
        await refresh(token); setModal(null); setModalPassword('');
      }
    } catch (e) { setModalError(String(e)); } finally { setBusy(false); }
  }

  const pendingIds = useMemo(() => new Set(records.map(r => r.appId)), [records]);
  const shownApps = useMemo(() => apps.filter(a => !pendingIds.has(a.id) && `${a.name} ${a.publisher}`.toLocaleLowerCase('pt-BR').includes(query.toLocaleLowerCase('pt-BR'))), [apps, pendingIds, query]);
  const shownRecords = useMemo(() => records.filter(r => r.name.toLocaleLowerCase('pt-BR').includes(query.toLocaleLowerCase('pt-BR'))), [records, query]);

  if (initialized === null) return <main className="startup"><Shield size={40} /><p>Carregando Blind Guardian…</p><ErrorLine error={error} /></main>;

  if (!token) return <main className="login-shell"><section className="login-panel" aria-labelledby="login-title">
    <div className="brand-mark"><Shield size={38} /></div>
    <h1 id="login-title">Blind Guardian</h1>
    <p className="text-secondary">{quitRequested ? 'Entre para confirmar o encerramento' : initialized ? 'Acesso administrativo' : 'Configurar senha administrativa'}</p>
    <form onSubmit={handleLogin}>
      <label className="form-label" htmlFor="username">Username</label>
      <input id="username" className="form-control mb-3" value={username} onChange={e => setUsername(e.target.value)} autoComplete="username" required disabled={!initialized} />
      <label className="form-label" htmlFor="password">Senha</label>
      <PasswordField value={password} onChange={setPassword} />
      {!initialized && <><label className="form-label mt-3" htmlFor="confirm-password">Confirmar senha</label><PasswordField id="confirm-password" value={confirmPassword} onChange={setConfirmPassword} /><small className="text-secondary">Mínimo de 12 caracteres. Configuração local de desenvolvimento.</small></>}
      <div className="mt-3"><ErrorLine error={error} /></div>
      <button className="btn btn-primary w-100" disabled={busy}>{busy ? 'Aguarde…' : initialized ? 'Entrar' : 'Configurar e entrar'}</button>
    </form>
    <p className="alpha-note">Versão experimental · proteção de aplicativos não ativada</p>
  </section></main>;

  return <div className="app-shell">
    <header className="app-header"><div className="header-brand"><Shield /><span>Blind Guardian</span><span className="alpha-pill">ALPHA</span></div><div className="header-actions"><span className="service-state" title={service}><i className="bi bi-exclamation-circle" /> Proteção não validada</span><button className="btn btn-sm btn-outline-secondary" title="Configurações" aria-label="Configurações" onClick={() => setSettingsOpen(true)}><i className="bi bi-gear" /></button><button className="btn btn-sm btn-outline-secondary" title="Encerrar sessão" onClick={() => { void api.logout(); setToken(null); }}><i className="bi bi-box-arrow-right" /> <span className="hide-small">Sair</span></button></div></header>
    <main className="content"><div className="status-banner" role="status"><i className="bi bi-shield-exclamation" /><span>Esta versão organiza solicitações de proteção. Nenhum aplicativo está bloqueado pelo Blind Guardian.</span></div>
      <div className="toolbar"><div className="tabs" role="tablist" aria-label="Programas"><button role="tab" aria-selected={tab === 'installed'} className={tab === 'installed' ? 'active' : ''} onClick={() => setTab('installed')}>Programas instalados</button><button role="tab" aria-selected={tab === 'protected'} className={tab === 'protected' ? 'active' : ''} onClick={() => setTab('protected')}>Programas bloqueados <span className="count">{records.length}</span></button></div><button className="btn btn-sm btn-outline-secondary refresh" onClick={() => { setBusy(true); void refresh(token).catch(e => setError(String(e))).finally(() => setBusy(false)); }} disabled={busy} title="Atualizar"><i className="bi bi-arrow-clockwise" /></button></div>
      <div className="search-row"><div className="search-box"><i className="bi bi-search" /><input aria-label="Pesquisar programas" placeholder="Pesquisar programas" value={query} onChange={e => setQuery(e.target.value)} /></div></div>
      <ErrorLine error={error} />
      {tab === 'installed' ? <><div className="list-head"><span>Programa</span><span>Versão</span><span>Fabricante</span><span /></div><div className="app-list">{shownApps.map(app => <div className="app-row" key={app.id}><div className="app-title"><AppIcon app={app} /><div><strong>{app.name}</strong>{!app.executable && <small>EXE não identificado</small>}</div></div><span className="muted-cell">{app.version || '—'}</span><span className="muted-cell">{app.publisher || '—'}</span><button className="btn btn-sm btn-outline-primary" disabled={!app.executable} onClick={() => setModal({ kind: 'protect', appId: app.id, name: app.name })}>Preparar bloqueio</button></div>)}{shownApps.length === 0 && <div className="empty">Nenhum programa encontrado.</div>}</div>
        <form className="manual-add" onSubmit={e => { e.preventDefault(); setBusy(true); void api.addManual(token, manualPath).then(() => { setManualPath(''); return refresh(token); }).catch(e => setError(String(e))).finally(() => setBusy(false)); }}><label htmlFor="manual-path">Adicionar EXE manualmente</label><div className="input-group"><input id="manual-path" className="form-control" placeholder="C:\Caminho\programa.exe" value={manualPath} onChange={e => setManualPath(e.target.value)} required /><button className="btn btn-outline-secondary" disabled={busy}>Adicionar</button></div></form>
      </> : <><p className="list-caption">Somente “Proteção ativa” significa bloqueio verificado. Solicitações pendentes não impedem execução.</p><div className="list-head protected-head"><span>Programa</span><span>Estado</span><span /></div><div className="app-list">{shownRecords.map(record => { const app = apps.find(a => a.id === record.appId); return <div className="app-row protected-row" key={record.appId}><div className="app-title">{app ? <AppIcon app={app} /> : <span className="app-icon fallback-icon"><i className="bi bi-app" /></span>}<div><strong>{record.name}</strong><small>{record.detail}</small></div></div><span className={`state-chip state-${record.state}`}>{labels[record.state]}</span><div className="row-actions"><button className="btn btn-sm btn-outline-secondary" onClick={() => setModal({ kind: 'launch', appId: record.appId, name: record.name })}>Senha</button><button className="btn btn-sm btn-outline-secondary" onClick={() => setModal({ kind: 'remove', appId: record.appId, name: record.name })}>Remover</button></div></div>; })}{shownRecords.length === 0 && <div className="empty">Nenhum programa cadastrado.</div>}</div></>}
    </main><footer>Desenvolvido por Raphael Laurentino <span>·</span> v0.1.0-alpha <span>·</span> <a href="https://github.com/RaphaelTW" onClick={e => { e.preventDefault(); void openUrl('https://github.com/RaphaelTW'); }}>GitHub <i className="bi bi-box-arrow-up-right" /></a></footer>
    {settingsOpen && <SettingsDialog token={token} service={service} onClose={() => setSettingsOpen(false)} onChanged={() => { setSettingsOpen(false); setToken(null); setUsername(''); }} />}
    {modal && <div className="modal-backdrop-custom" onMouseDown={e => { if (e.target === e.currentTarget) setModal(null); }}><section className="auth-modal" role="dialog" aria-modal="true" aria-labelledby="modal-title" onKeyDown={e => { if (e.key === 'Escape') setModal(null); }}><div className="modal-top"><div className="modal-symbol"><i className={`bi bi-${modal.kind === 'launch' ? 'lock' : modal.kind === 'quit' ? 'power' : 'shield-lock'}`} /></div><button className="close-button" aria-label="Fechar" onClick={() => setModal(null)}><i className="bi bi-x-lg" /></button></div><h2 id="modal-title">{modal.kind === 'launch' ? 'Aplicativo protegido' : modal.kind === 'quit' ? 'Encerrar Blind Guardian' : modal.kind === 'protect' ? 'Preparar bloqueio' : 'Remover solicitação'}</h2><p className="text-secondary">{modal.kind === 'launch' ? `Informe a senha de autorização para ${modal.name}.` : modal.kind === 'quit' ? 'Confirme suas credenciais para encerrar.' : `${modal.name} · confirmação administrativa`}</p><form onSubmit={runModal}>{modal.kind !== 'launch' && <><label htmlFor="modal-user" className="form-label">Username</label><input ref={firstInput} id="modal-user" className="form-control mb-3" value={modalUser} onChange={e => setModalUser(e.target.value)} required autoComplete="username" /></>}<label htmlFor="modal-password" className="form-label">Senha</label><PasswordField id="modal-password" value={modalPassword} onChange={setModalPassword} inputRef={modal.kind === 'launch' ? firstInput : undefined} />{modal.kind === 'quit' && <label className="form-check mt-3"><input className="form-check-input" type="checkbox" checked={quitConfirmed} onChange={e => setQuitConfirmed(e.target.checked)} /><span className="form-check-label">Confirmo que quero encerrar</span></label>}<div className="mt-3"><ErrorLine error={modalError} /></div><div className="modal-buttons"><button type="button" className="btn btn-outline-secondary" onClick={() => setModal(null)}>Cancelar</button><button className="btn btn-primary" disabled={busy}>{busy ? 'Aguarde…' : modal.kind === 'launch' ? 'Abrir aplicativo' : 'Confirmar'}</button></div></form></section></div>}
  </div>;
}
