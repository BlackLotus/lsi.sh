# lsi.sh
Fork of lsi.sh from https://calomel.org/megacli_lsi_commands.html
This code is distributed under the CC BY-SA 4.0 License

# What is this?
A bash wrapper for the megacli tool from LSI to manage MegaRaid clusters.
The megacli-tool is notorious for being cryptic/hard to use [1].

There is also a new tool called storcli [2] which is much nicer to use, but still not as intuitive as it could be.

# Usage
Open the lsi.sh file and edit your settings (path and enclosure) for more info visit the post at the beginning of the readme.

```
[root@cluster ~]# ./lsi 
Found ENCLOSURE Device ID: 32

              OBPG  .:.  lsi.sh
  -----------------------------------------------------
  status        = Status of Virtual drives (volumes)
  drives        = Status of hard drives
  ident $slot   = Blink light on drive (need slot number)
  good $slot    = Simply makes the slot \Unconfigured(good)\ (need slot number)
  replace $slot = Replace \Unconfigured(bad)\ drive (need slot number)
  remove $slot  = Remove hard drive from controller
  progress      = Status of drive rebuild
  errors        = Show drive errors which are non-zero
  bat           = Battery health and capacity
  batrelearn    = Force BBU re-learn cycle
  logs          = Print card logs
  checkNemail   = Check volume(s) and send email on raid errors
  allinfo       = Print out all settings and information about the card
  settime       = Set the raid card's time to the current system time
  setdefaults   = Set preferred default settings for new raid setup
  alarm         = Enable (1) or disable (0) the alarm sound
  jbod          = Enable (1) or diable (0) jbod
  raid0         = Set single harddisk to raid0
  create-jbod   = Set single harddisk to jbod
```

[1]: http://lmgtfy.com/?q=megacli
[2]: https://www.broadcom.com/support/download-search/?pg=&pf=&pn=&po=&pa=&dk=storcli
