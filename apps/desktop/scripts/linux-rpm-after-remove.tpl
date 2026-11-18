#!/bin/bash

if type update-alternatives >/dev/null 2>&1; then
    update-alternatives --remove '${executable}' '/opt/${sanitizedProductName}/${executable}' || true
    update-alternatives --remove 'dsh' '/opt/${sanitizedProductName}/resources/runtime/cli/bin/dsh' || true
else
    rm -f '/usr/bin/${executable}' '/usr/bin/dsh'
fi
