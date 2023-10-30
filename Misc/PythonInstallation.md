# Python3 installation

Task was to install python3 on machines:

- eleclab-tcad00
- eleclab-tcad01
- ~~eleclab-tcad02~~
- eleclab-tcad04

## Installation

```
[user@eleclab-tcad00 ~]$ sudo su -
[root@eleclab-tcad00 ~]$ yum install python3 -y

[user@eleclab-tcad00 ~]$ python3 --version
Python 3.6.8

```

## Usage

```
[user@eleclab-tcad00 ~]$ python3
Python 3.6.8 (default, Apr  2 2020, 13:34:55)
[GCC 4.8.5 20150623 (Red Hat 4.8.5-39)] on linux
Type "help", "copyright",
"credits" or "license" for more information.
>>> print("Hello World!")
Hello World!
>>>
```

## Uninstallation

```
[user@eleclab-tcad00 ~]$ sudo su -
[root@eleclab-tcad00 ~]$ yum remove python3 -y
```

## Problems

Unable to install python3 on eleclab-tcad02, reason being that it is a CentOS 8 machine and installing python3 attempts to update `BaseOS` module and fails with error:

```
Error: Failed to download metadata for "extra": cannot download repomd.xml: Cannot download repodata/repomd.xml: All mirrors were tried
```

Needs consultation with IT team.
