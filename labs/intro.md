## Lab exercise 0: Setup steps

:imagesdir: images

### Accessing your dedicated lab environment using your provided GUID

On your laptop, browse to https://www.opentlc.com/gg/gg.cgi?profile=generic_summit[*Lab GUID Assignment page*^].
From this page, you will be assigned your unique GUID, which you will use to access your unique lab environment and systems.

Select the proper *Lab Code* from the drop down list. Find the lab `XXXXXXX - Hands on with Red Hat Multi-Cluster Federation: Application Portability`
The activation key is *XXXXXXX*.

The resulting *Lab Information page* will display your lab's GUID and other useful information about your lab environment.
Take note of your assigned GUID.
You will use this GUID to access your lab's environment and systems.
Your unique GUID will also be embedded in your lab environment's host names.
From this *Lab Information page*, you will also be able to access your unique lab environment's power control and consoles.
Go to the last bullet point and click on *here* to access the environment's power control and consoles.

image:labinfopage.png[1200,1200]

Notice that one workstation VM is shown on the power control and consoles page.
This is a Red Hat Enterprise Linux 8 system with GUI and will be the machine that we will use throughout all the lab exercises in this lab.
Click the *CONSOLE* button.
Log in as Lab User with password *r3dh4t1!*.

image:vmconsole.png[200,200]

Congratulations, you got to your *graphical console*.


## Using the text console to access the remote shell

On your laptop (i.e. not in the browser window with the remote deskop), open the `Terminal` application.
Then, enter the following command, replacing `GUID` with your actual GUID:

```
[... ~]$ ssh lab-user@workstation-GUID.rhpds.opentlc.com
```

For example, if your `GUID` was `3fa1`, you would execute: `$ ssh lab-user@workstation-3fa1.rhpds.opentlc.com`

If everything goes correctly, you will end up in the lab's test system shell.
You can tell that by listing the directory with lab exercises:

```
[... ~]$ cd
[... ~]$ ls labs
lab1_introduction  lab2_openscap  lab3_profiles  lab4_ansible  lab5_oval
```

Congratulations, now you got to your *text console*.


link:README.adoc#table-of-contents[ Table of Contents ] | link:lab1_introduction.adoc[Lab exercise 1: Say Hello to ComplianceAsCode]


## Lab Related Tips

This section contains various tips that may be useful to keep in mind as you are doing the lab exercises.


### Command listings

Shell session listings obey the following convention:

```
[... ~]$ pwd
/home/lab-user
[... ~]$ cd labs
[... labs]$ ls
lab1_introduction  lab2_openscap  lab3_profiles  lab4_ansible  lab5_oval
[... labs]$ cat /etc/passwd
...
lab-user:x:1000:1000:Lab User:/home/lab-user:/bin/bash
```

- Commands, in this example `pwd` and `cat /etc/passwd`, are prefixed by `[...` followed by the respective directory name and `]$`.
For reference, in the actual terminal, commands are prefixed also by the current username and hostname, for example `[lab-user@workstation-3fa1 ~]$`.
- Lines that follow commands and that are not commands themselves represent the last command's output.
In the example above, the output of the `ls` command in the `labs` directory are directories with lab exercises.
- Ellipsis may be used to indicate that there are multiple output lines, but as they are of no interest, they are omitted.
In the example above, the output of the `cat /etc/passwd` contains lots of lines, and we have emphasized the line containing lab-user's entry.


### Copy and Pasting

Normally, when you select text you want to copy in the document, you press `Ctrl+C` to copy it to the system clipboard, and you paste it from the clipboard to the editor using `Ctrl+V`.

Keep in mind that when you paste to the **terminal console** or **terminal editor**, you have to use `Ctrl+Shift+V` instead of the `Ctrl+V`.
The same applies when copying from the terminal window - you have to use `Ctrl+Shift+C` after selecting the text, not just `Ctrl+C`.


### Searching in the browser

When told to search for a occurrence of text in the Firefox browser, you have following possibilities:

- Press `Ctrl+F`, which will bring up the search window.
- Click the "hamburger menu" at the top right corner, and click the `Find in This Page` entry.
This is the same as the previous step, but it is useful if you have problems with the keyboard shortcut.

image:0-04-find_in_page.png[600,600]

- If the browser has the link:https://addons.mozilla.org/en-US/firefox/addon/find-in-page-with-preview/[Find in Page] extension installed, there is a blue icon close to the "hamburger menu" at the top right part of the browser.
You can click it, and start typing the text to search for.
The extension will display surroundings of the web page next to occurrences of the expression.

image:0-05-supersearch.png[600,600]

Next Lab:  [Lab 1 - Introduction and Prerequisites](./1.md)<br>
[Home](../README.md)
