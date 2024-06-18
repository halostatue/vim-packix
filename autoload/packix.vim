scriptencoding utf-8

import "packix.vim"

function! packix#version()
  return s:packix.Version()
endfunction

function! packix#setup(Callback, opts = {})
  call s:packix.Setup(a:Callback, a:opts)
endfunction

function! packix#init(opts = {})
  call s:packix.Init(a:opts)
endfunction

function! packix#add(name, opts = {})
  call s:packix.Add(a:name, a:opts)
endfunction

function! packix#local(name, opts = {})
  call s:packix.Local(a:name, a:opts)
endfunction

function! packix#install(opts = {})
  call s:packix.Install(a:opts)
endfunction

function! packix#update(opts = {})
  call s:packix.Update(a:opts)
endfunction

function! packix#clean()
  call s:packix.Clean()
endfunction

function! packix#status()
  call s:packix.Status()
endfunction

function! packix#plugins()
  return s:packix.Plugins()
endfunction

function! packix#plugin_names()
  return s:packix.PluginNames()
endfunction

function! packix#get_plugin(name)
  return s:packix.GetPlugin(a:name)
endfunction

function! packix#has_plugin(name)
  return s:packix.HasPlugin(a:name)
endfunction

function! packix#is_plugin_installed(name)
  return s:packix.IsPluginInstalled(a:name)
endfunction
