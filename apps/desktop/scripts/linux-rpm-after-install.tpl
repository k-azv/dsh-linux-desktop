#!/bin/bash

if type update-alternatives >/dev/null 2>&1; then
    if [ -L '/usr/bin/${executable}' -a -e '/usr/bin/${executable}' -a "`readlink '/usr/bin/${executable}'`" != '/etc/alternatives/${executable}' ]; then
        rm -f '/usr/bin/${executable}'
    fi
    update-alternatives --install '/usr/bin/${executable}' '${executable}' '/opt/${sanitizedProductName}/${executable}' 100 || ln -sf '/opt/${sanitizedProductName}/${executable}' '/usr/bin/${executable}'
    if [ -L '/usr/bin/dsh' -a -e '/usr/bin/dsh' -a "`readlink '/usr/bin/dsh'`" != '/etc/alternatives/dsh' ]; then
        rm -f '/usr/bin/dsh'
    fi
    update-alternatives --install '/usr/bin/dsh' 'dsh' '/opt/${sanitizedProductName}/resources/runtime/cli/bin/dsh' 100 || ln -sf '/opt/${sanitizedProductName}/resources/runtime/cli/bin/dsh' '/usr/bin/dsh'
else
    ln -sf '/opt/${sanitizedProductName}/${executable}' '/usr/bin/${executable}'
    ln -sf '/opt/${sanitizedProductName}/resources/runtime/cli/bin/dsh' '/usr/bin/dsh'
fi

chmod 4755 '/opt/${sanitizedProductName}/chrome-sandbox' || true

if hash update-mime-database 2>/dev/null; then
    update-mime-database /usr/share/mime || true
fi

if hash update-desktop-database 2>/dev/null; then
    update-desktop-database /usr/share/applications || true
fi
