summary: Access control support for MUCs.

Introduction
============

This module allows restricting access to MUCs based on lists containing JIDs
or domain names.

Dependencies
============

None.

Installation
============

Copy the module to the prosody modules directory.

Configuration
=============

The module should be added to the list of modules of the muc component in the
config file.

    Component "conference.example.com" "muc"
      modules_enabled = {
        ...
        "mod_muc_acl";
        ...
      }
      muc_acls = {
        chatroom = {
            "user@jabber.example.com",
            "example.com",
            "user@examplejabber.com"
        }
     }

The above example allows all users of the example.com server plus the two users
user@jabber.example.com and user@examplejabber.com access to a muc called
"chatroom".

The following describes the configuration options available:


Name                                | Default   | Description
----------------------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
muc\_acls                           | {}        | Table in key/value format. The key is the name of the muc (the part before the @), the value is a list of user jids or domains that are allowed to access each muc.
muc\_acl\_public\_rooms             | {}        | List (comma separated) of mucs which can be accessed by any jabber user of any server. (**muc\_acl\_restricted\_by\_default** must be set to true)
muc\_acl\_default                   | {}        | Default access list. It can contain JIDs or domain names and will be applied to restrict access to all rooms which are neither in the **muc\_acl\_public\_rooms** list nor the **muc\_acls** list. (**muc\_acl\_restricted\_by\_default** must be set to true)
muc\_acl\_restricted\_by\_default   | false     | Restricts access to all mucs by default.
muc\_acl\_debug                     | false     | Enables debugging. (debug logging must be enabled in prosody)


What does not work / Limitations
================================

**There are no negative matching options**

If you want to allow all but a few users access to a specific muc, one will have to maintain
a list of allowed users. It is not (yet) possible to allow access to all users of a domain but
exclude some.

**Contradictory settings**

There is no protection/recognition of contradictory settings.
I.e. a room is set to be public using the **muc\_acl\_public\_rooms** and
**muc\_acl\_restricted\_by\_default** is set to 'true' but access to the same room
is restricted using the **muc\_acl** option. In this case, the **muc\_acl**
setting would be ignored.

Compatibility
=============

------ | -------------
0.10   | Untested
0.9    | Works
0.8    | Should work


Attribution
===========

This module is based on Matthew Wild's work, which can be found in the
official Prosody modules repository:
https://modules.prosody.im/mod_muc_access_control.html
