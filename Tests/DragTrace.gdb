# Temporary debugger trace. Continue immediately at each breakpoint; detach
# after comparing a desktop drop with a drop inside a Finder folder window.
set pagination off
set confirm off
set logging file /tmp/classic-drag30.log
set logging overwrite on
set logging on
break *0x5e05b5e0
commands
silent
printf "DRAG begin ref=%08x\n", $r3
continue
end
break *0x5e05b830
commands
silent
printf "DRAG result=%d ref=%08x\n", $r3, $r30
continue
end
break *0x5e05bf08 if $r3 != 3
commands
silent
printf "TRACK msg=%d window=%08x ref=%08x arg=%08x\n", $r3, $r4, $r6, $r5
continue
end
break *0x5e05c1dc
commands
silent
printf "RECEIVE r3=%08x window=%08x r5=%08x r6=%08x\n", $r3, $r4, $r5, $r6
continue
end
break *0x5e05c2f8
commands
silent
printf "RECEIVE result=%d attributes=%08x\n", $r28, *(unsigned int*)($r31+4)
continue
end
break *0x5e05bbd8
commands
silent
printf "INSTALL kind=%d window=%08x\n", $r3, $r4
continue
end
continue
