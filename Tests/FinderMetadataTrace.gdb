# Temporary catalog-save trace for an EMPTY diagnostic session. Detach after
# moving disposable icons and closing their window; never ship a traced host.
set pagination off
set confirm off
set logging file /tmp/classic-metadata32.trace
set logging overwrite on
set logging on
break *0x5e003500
commands
silent
printf "SAVE pb=%08x attr=%02x vol=%d dir=%d name=%08x dates=%08x/%08x/%08x flags=%04x point=%08x\n", $r3, *(unsigned char*)($r3+30), *(short*)($r3+22), *(int*)($r3+48), *(int*)($r3+18), *(int*)($r3+72), *(int*)($r3+76), *(int*)($r3+80), *(unsigned short*)($r3+40), *(int*)($r3+42)
if *(int*)($r3+18)
x/20bx *(int*)($r3+18)
end
continue
end
break *0x5e02034c
commands
silent
printf "RESULT=%d\n", $r3
continue
end
continue
