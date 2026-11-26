!macro NSIS_HOOK_PREINSTALL
  nsExec::ExecToLog '$SYSDIR\sc.exe stop BlindGuardianService'
  Pop $0
!macroend

!macro NSIS_HOOK_POSTINSTALL
  IfFileExists "$INSTDIR\resources\blind-guardian-service.exe" +2 0
    Abort "Blind Guardian Service ausente no instalador."
  ExecWait '"$INSTDIR\resources\blind-guardian-service.exe" --install' $0
  ${If} $0 != 0
    Abort "Falha ao registrar ou iniciar Blind Guardian Service (codigo $0)."
  ${EndIf}
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  IfFileExists "$INSTDIR\resources\blind-guardian-service.exe" service_exists service_done
  service_exists:
  ExecWait '"$INSTDIR\resources\blind-guardian-service.exe" --uninstall' $0
  ${If} $0 != 0
    Abort "Falha ao remover Blind Guardian Service (codigo $0)."
  ${EndIf}
  service_done:
!macroend
