# Perl CyanChat Client

## I. About PCCC

Perl CyanChat Client 2.x is a complete rewrite from the original
1.x versions. The new client uses `Net::CyanChat` to connect to
the CyanChat servers instead of having the code included within
PCCC's own code.

PCCC 1.x was actually written prior to Net::CyanChat which I
created AFTER making PCCC 1.x, so the new PCCC makes up for that.

## II. About CyanChat

CyanChat is the name of a chat room which is owned by Cyan Worlds,
Inc. (formerly known simply as Cyan). They created some really good
adventure games named Myst and Riven (and Myst III and then Myst IV
and V too), as well as a few other spinoff games such as Uru and
RealMyst.

The chat server was programmed by Mark Deforest of Cyan Worlds. The
chat room was created so that fans of Cyan could have a place to
meet and discuss their games and novels and interact with other fans.
The "CyanChat Community" is made up of a small number of members who
have been with CyanChat for years and years (I first went to CyanChat
like six years ago and the same group of people are still here today!)

The official homepage to CyanChat is:  http://cho.cyan.com/chat/

## III. CyanChat Rules and Policies

Official Rules Page: http://cho.cyan.com/chat/rules.html

* Be respectful of and sensitive to others.
* Please, no platform wars ("my computer is better than yours").
* Keep it "G" rated; in other words, suitable for family viewing.
* No flooding, in other words, filling the screen with junk.
* But most of all HAVE FUN!

### A. Impersonating

No name or handle is reserved for any one person.
However, purposely impersonating someone for personal
gain or in disrespect of the person being impersonated
will not be tolerated. So, please try to find a
unique name for yourself.

### B. Being Banned

The CyanChat server has a bad language filter that
watches all the messages being sent. If it detects
that you have used bad language, depending how severe,
it might automatically ban you from using CyanChat,
ban you for a day or just censor the message. Once
you have been banned you will get a message when you
start CyanChat that your IP address has been blocked
from using CyanChat.

### C. Getting Unbanned

There are many reasons why an IP address might be banned
from CyanChat, some reasons are accidental, such as misspelling
a word. If you've gotten accidentally banned, e-mail markd@cyan.com
with the IP address that is banned. But one thing to
remember is that I have a log of all the bannings (and what
was said) and its usually quite obvious, so don't try the
"accident" angle unless it really was.

## IV. Configuring PCCC

After running PCCC for the first time, you can configure CyanChat
by choosing "Edit -> Preferences". The client assumes a number of default
preferences, which you can change. If you want to restore them to their
defaults, either delete "config.txt" and restart the program, or click
"Restore Defaults" in the preferences window.

## V. Using PCCC

When you open PCCC, it should connect automatically unless you specified
that it shouldn't. In that case, click "Connection -> Connect" on the menu
bar to connect to CyanChat.

When connected, you will receive a lot of messages from ChatServer. These
are introduction messages.

Type a nickname for yourself in the box next to the word "Name:" toward
the top of the window. Then click "Join Chat" to enter the room. Note that
nicknames can be no longer than 20 characters and that they can't contain
the pipe symbol `|`.

Write messages into the long text box above the chat dialog space. To send
a private message to somebody, there are three options you can use:

1. Write a message into the normal message space, then single-click
			the target's name from the Who List, and click "Send Private"
2. Double-click a user's name from the Who List to open a Private
			Message window. Type your message into this window and hit Enter.
3. In the normal message space, type `/whisper <name> <message>`,
			substituting a user's name for `<name>` and a message for `<message>`.

To exit the chat room, click the "Exit Chat" button. To disconnect from
CyanChat, click "Connection -> Disconnect". Doing this will also sign you
out if you are currently signed in to the chat room.

Exiting PCCC via "File -> Exit" will also sign you out and disconnect you
where applicable. Closing out of the program in any other means will result
in a "disconnect", where CyanChat will simply tell the other users that you
were disconnected rather than that you signed out properly.

## VI. Installation

Perl CyanChat Client should work fine on all operating systems. It mostly
uses the standard Tk modules from Tk version 804.027

In addition to the standard Tk modules, the following nonstandard modules
may need to be installed:

	Net::CyanChat 0.04 or higher.

These modules have been included in the standard distribution of
Perl CyanChat Client.

## VII. License and Copyright

    Perl CyanChat Client
    Copyright (C) 2006-13  Noah Petherbridge

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
