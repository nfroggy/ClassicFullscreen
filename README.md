# ClassicFullscreen

This is a launcher that patches various parts of the Classic environment in order to allow running Classic in fullscreen, complete with the OS 9 Finder and Control Strip.

## AI Disclaimer

All of the code in this repo was written by AI. I wrote the readme myself (isn't AI writing annoying?)

## What's the point?

Classic has poor graphics performance, especially when running software that needs 256 color mode. However, running software under Classic does have some benefits. You can run OS X and OS 9 software at the same time, and you get better memory management as it's handled through OS X. If an OS 9 program crashes, you can just reboot the Classic environment instead of your whole computer. Most importantly, a lot of later PowerPC Macs don't support booting OS 9 natively, and as a result can only run OS 9 software through Classic. The OS 9 community has done a great job of getting OS 9 to run on a lot of Macs that Apple didn't support, but there are often still problems with stuff like audio, graphics, power management, Wi-Fi, USB 2.0, and more depending on the model.

The goal with this project was to have the "best of both worlds". You can run OS 9 software within OS X with all the benefits of this, and get full hardware support since all the hardware access goes through OS X. However, it feels like you're running OS 9 natively.

## How to run

1. Install Mac OS X 10.4 on your computer, then install all updates through Software Update.
2. Install Classic using a 9.2.2 system folder and applications folder. If you don't have one, or if the launcher complains about a file not matching, [this one](https://macintoshgarden.org/apps/mac-os-922-powermac-g4-mdd) works.
3. Start Classic normally through the settings pane. It will say it's updating the system folder. If you used the system folder I linked above, it will complain about Quicktime. Stop Classic.
4. If it complained about Quicktime, start Classic through the settings pane again. It will complain about Quicktime again. Check "don't show again". Stop Classic.
5. Run Classic through the fullscreen launcher. It will ask for your password due to having to patch system files, then launch Classic in fullscreen. You should see the OS 9 Finder and Control Strip (if your system folder has Control Strip) and can run OS 9 software at this point.

## Usage tips

- Once you're in fullscreen Classic, your running OS X software will show up in the application switcher. Clicking on an OS X application will switch from Classic back to OS X. You can then switch back to OS 9 by clicking the icon of a running OS 9 program or the ClassicFullscreen launcher in the dock.

- If Classic freezes, you can force-quit it by pressing Cmd+Opt+Ctrl+F12. Note that you also have to press "fn" on a Mac layout keyboard.

## Hardware compatibility

- This only works on single monitor setups.

- I have tested this on both of the late-era PowerPC Macs I own, an iBook G4 and a Mac Mini G4. However, both of them have the same GPU, the Radeon 9200. Hopefully it works on other systems as well. It would be particularly interesting to see if this worked on a G5, as they are not capable of booting OS 9 natively at all without doing some major modifications to the operating system.
