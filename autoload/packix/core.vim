vim9script

import autoload 'packix/plug.vim'

type Opts = dict<any>

export const SLASH = exists('+shellslash') && !&shellslash ? '\' : '/'
export const HAS_TIMERS = has('timers')
export const IS_WINDOWS = has('win32')

export const NAVIGATE_PLUGINS =
  "Use <C-j> and <C-k> to navigate between plugins."
export const PLUGIN_UPDATES =
  "Press 'D' on an updated plugin to preview the latest updates."
export const PLUGIN_DETAILS =
  "Press 'O' on a plugin to preview plugin details."
export const PREVIEW_COMMIT =
  "Press 'Enter' on commit lines to preview the commit."
export const QUIT_BUFFER =
  "Press 'q' to quit this buffer."
export const VIEW_ERRORS =
  "Press 'E' on plugins with errors to view output."
export const INSTALLED =
  "Installed!"
export const UPDATED =
  "Updated!"
export const UP_TO_DATE =
  "Already up to date."
export const LOCAL_UP_TO_DATE =
  "Local plugin already up to date."

export const BUFFER = '__packix__'
export const FILETYPE = 'packix'

export def Wrap(v: any): list<any>
  return v == null ? [] : v->type() == v:t_list ? v : [v]
enddef

export def WithShell(Fn: func(): any): any
  var saved = [&shell, &shellcmdflag, &shellredir]

  if IS_WINDOWS
    set shell=cmd.exe shellcmdflag=/c shellredir=>%s\ 2>&1
  else
    set shell=sh shellredir=>%s\ 2>&1
  endif

  var result: any

  try
    result = Fn()
  finally
    [&shell, &shellcmdflag, &shellredir] = saved
  endtry

  return result
enddef

export def System(cmd: any): list<string>
  if cmd->type() != v:t_string && cmd->type() != v:t_list
    throw 'Invalid command type, it must be a string or list<string>'
  endif

  return WithShell(
    () => systemlist(cmd->type() == v:t_string ? cmd : cmd->join(' '))
  )
enddef

def AsyncOnStdout(Callback: func, opts: Opts, _jobId: number, message: any, event: string): Opts
  if event ==? 'exit'
    Callback(opts.out)
  endif

  const lines = message->type() == v:t_string ? [message] : message

  for line in lines
    opts.out->add(line)
  endfor

  return opts
enddef

export def SystemAsync(cmd: any, Callback: func, opts: Opts = {})
  var Ref = function(AsyncOnStdout, [Callback, { out: [] }])

  var jobOpts = { on_stdout: Ref, on_stderr: Ref, on_exit: Ref, }
  var job = WithShell(() => jobs.Start(cmd, jobOpts))

  if job <= 0
    Callback([])
  endif
enddef

export def Confirm(question: string): bool
  return ConfirmWithOptions(question, "&Yes\nNo") ==? 1
enddef

export def ConfirmWithOptions(question: string, options: string): number
  silent! exec 'redraw'

  try
    return question->confirm(options)
  catch
    return 0
  endtry
enddef

export def Trim(str: string): string
  return str->substitute('^\s*\(.\{-}\)\s*$', '\1', '')
enddef

export def Setline(line: number, content: any)
  if content->type() != v:t_string && content->type() != v:t_list
    throw 'Invalid content type, must be a string or list<string>'
  endif

  var window = bufwinnr(BUFFER)

  if window < 0
    return
  endif

  if winnr() !=? window
    silent! exec ':' .. window .. 'wincmd w'
  endif

  setline(line, content)
enddef

export def SymlinkCommand(src: string, dest: string): string
  if executable('ln')
    return printf('ln -sf %s %s', shellescape(src), shellescape(dest))
  endif

  if has('win32') && executable('mklink')
    return printf('mklink %s %s', shellescape(src), shellescape(dest))
  endif

  return null_string
enddef

export def NameToUrl(name: string): string
  return name =~? '^\(http\|git@\|git+ssh\).*'
    ? name
    : printf('https://github.com/%s', name)
enddef

# Handle demand-loaded 'opt' plugins.
final DeferredCommands: dict<list<plug.Plugin>> = {}

export def DeferCommand(trigger: string, plugin: plug.Plugin)
  if !DeferredCommands->has_key(trigger)
    var fcall = printf('call RunDeferredCommand("%s", "<bang>", <line1>, <line2>, <q-args>)', trigger)
    var cmd = printf('command! -nargs=* -range -bang -complete=file %s %s', trigger, fcall)

    execute cmd
  endif

  DeferredCommands[trigger] = DeferredCommands->get(trigger, [])->add(plugin)
enddef

def RunDeferredCommand(name: string, bang: any, line1: any, line2: any, args: any)
  if !DeferredCommands->has_key(name)
    throw $'Command {name} is not deferred.'
  endif

  execute $'delcommand {name}'

  var plugins = DeferredCommands[name]

  remove(DeferredCommands, name)

  for plugin in plugins->reverse()
    plugin.RemoveTriggers()

    try
      execute $'packadd {plugin.name}'

      if exists($'#User#{plugin.name}')
        execute $'doautocmd <nomodeline> User {plugin.name}'
      endif
    catch /^Vim\%((\a\+)\)\=:E919:/
    endtry
  endfor

  var range = (line1 == line2 ? '' : ($'{line1},{line2}'))

  execute $'{range}{name}{bang} {args}'
enddef
