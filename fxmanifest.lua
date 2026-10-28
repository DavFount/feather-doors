fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'feather-doors'
description 'Authoritative door domain for the Feather Framework (scaffold)'
author 'Feather Framework'
version '0.1.0-dev'

shared_scripts {
    'shared/constants.lua'
}

server_scripts {
    'server/main.lua'
}

client_scripts {
    'client/native.lua',
    'client/main.lua'
}

files {
    'client/native.lua'
}
