# Sleep diagnostic for this measured session only: HOST PID 3966.
# PEF file base 0x2c9c0; Finder file base 0x3f983000.
# Re-resolve both bases before reuse after a restart.
set pagination off
set confirm off
set logging file /tmp/classic-sleep-calls.log
set logging overwrite on
set logging on
break *0x3faa7eb0
commands
silent
printf "Finder menu Sleep tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x3faec7e4
commands
silent
printf "Finder _Sleep wrapper tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x3faa7ee0
commands
silent
printf "Finder menu Sleep returned tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x365b8
commands
silent
printf "__SleepDispatch tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x392bc
commands
silent
printf "Sleep tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x368a4
commands
silent
printf "EnqueueMPSleepRequest tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x39030
commands
silent
printf "SleepGuts tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x39138
commands
silent
printf "WeShouldDoze result tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x37594
commands
silent
printf "HandleDoze tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x3887c
commands
silent
printf "HandleSleep tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x38210
commands
silent
printf "WaitFromSleep tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x39398
commands
silent
printf "WakeFromDoze tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x39284
commands
silent
printf "SleepGuts return tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x37398
commands
silent
printf "RunSleepQueue tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
break *0x5e012bb8
commands
silent
printf "Host IOKit power notification tick=%08x r3=%08x r4=%08x r5=%08x lr=%08x\n", *(unsigned int*)0x16a, $r3, $r4, $r5, $lr
continue
end
continue
