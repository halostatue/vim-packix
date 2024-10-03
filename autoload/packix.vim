vim9script

# vim-packix
#
# Vim 9 plugin manager, available under the MIT license
#
# Copyright 2024 Austin Ziegler
#
# - Based on https://github.com/kristijanhusak/vim-packager, copyright
#   2018–2021 Kristijan Husak and other contributors
# - Partially based on https://github.com/prabirshrestha/async.vim, copyright
#   2016–2024 Prabir Shrestha and other contributors
#
# The MIT License (MIT)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

if exists('g:loaded_vim_packix') && g:loaded_vim_packix == true
  finish
endif

g:loaded_vim_packix = true

type Opts = dict<any>

import autoload 'packix/core.vim'
import autoload 'packix/git.vim'
import autoload 'packix/jobs.vim'
import autoload 'packix/plug.vim'
import autoload 'packix/status.vim'

export class Packix
  var _commandType: string = ''
  var _depth: number = 5
  var _enableDefaultMappings: bool = true
  var _installRan: bool = false
  var _jobsLimit: number = 8
  var _lastRenderTime: list<number>
  var _plugins: dict<plug.Plugin> = {}
  var _pluginNames: dict<string> = {}
  var _postRunHooksCalled: bool = false
  var _postRunOpts: Opts = {}
  var _processedPlugins: list<plug.Plugin> = []
  var _remainingJobs: number = 0
  var _result: list<string>
  var _runningJobs: number = 0
  var _startTime: list<number>
  var _timer: number = -1
  var _updateRan: bool = false
  var _windowCmd: string = 'vertical topleft new'
  var _defaultPluginType: string = 'start'
  var _dir: string = [
    substitute(split(&packpath, ',')[0], '\(\\\|\/\)', core.SLASH, 'g'),
    'pack',
    'packix'
  ]->join(core.SLASH)

  static const VERSION = '1.1.0'

  def new(opts: Opts)
    if opts->has_key('dir')
      this._dir = opts.dir
        ->fnamemodify(':plugin')
        ->substitute($'\{core.SLASH}$', '', '')
    endif

    if opts->has_key('depth')
      this._depth = opts.depth
    endif

    if opts->has_key('jobs')
      this._jobsLimit = opts.jobs
    endif

    if opts->has_key('window_cmd')
      this._windowCmd = opts.window_cmd
    endif

    if opts->has_key('default_plugin_type')
      this._defaultPluginType = opts.default_plugin_type
    endif

    if opts->has_key('disable_default_mappings')
      this._enableDefaultMappings = !opts.disable_default_mappings
    endif

    this._lastRenderTime = reltime()

    silent! mkdir(printf('%s%s%s', this._dir, core.SLASH, 'opt'), 'p')
    silent! mkdir(printf('%s%s%s', this._dir, core.SLASH, 'start'), 'p')
  enddef

  def DefaultPluginType(): string
    return this._defaultPluginType
  enddef

  def Dir(): string
    return this._dir
  enddef

  def Add(url: string, opts: Opts = {})
    this._SavePlugin({ url: url, opts: opts })
  enddef

  def AddRequired(url: string, requiredPackage: any)
    if requiredPackage->type() == v:t_string
      Add(requiredPackage)
      return
    endif

    if requiredPackage->type() != v:t_dict
      throw $'`requires` values must be strings or dictionaries for `{url}`.'
    endif

    var requiredUrl: string = requiredPackage->get('url', '')
    var requiredOpts: Opts = requiredPackage->get('opts', {})

    if requiredUrl->empty()
      throw $'Missing `requires` package url for `{url}`.'
    endif

    this._SavePlugin({ url: requiredUrl, opts: requiredOpts })
  enddef

  def Local(path: string, opts: Opts = {})
    opts.local = true
    this._SavePlugin({ url: path, opts: opts })
  enddef

  def Install(opts: Opts)
    this._startTime = reltime()
    this._result = []
    this._processedPlugins = this._plugins
      ->values()
      ->filter((_, val: plug.Plugin) => !val.installed)

    var onlyPlugins: list<string> = opts->get('plugins', [])

    if !onlyPlugins->empty()
      this._processedPlugins = this._processedPlugins
        ->filter((_, val: plug.Plugin) => onlyPlugins->index(val.name) > -1)
    endif

    this._remainingJobs = this._processedPlugins->len()

    if this._remainingJobs ==? 0
      echo 'Nothing to install.'
      return
    endif

    this._installRan = true
    this._postRunOpts = opts

    this._OpenBuffer()

    if core.HAS_TIMERS
      this._timer = timer_start(100, (timer) => this._Render(), { repeat: -1 })
    else
      this._RenderIfNoTimers()
    endif

    for plugin in this._processedPlugins
      plugin.Queue()

      var command = plugin.Command(this._depth)

      if !command->empty()
        this._StartJob(
          command,
          {
            exit_handler: this._ExitHandler,
            handler: this._StdoutHandler,
            limit_jobs: true,
            plugin: plugin,
          }
        )
      endif
    endfor
  enddef

  def Update(opts: Opts)
    this._startTime = reltime()
    this._result = []
    this._processedPlugins = this._plugins
      ->values()
      ->filter((_, val: plug.Plugin) => val.frozen == false || val.local == false)

    var onlyPlugins: list<string> = opts->get('plugins', [])

    if !onlyPlugins->empty()
      this._processedPlugins = this._processedPlugins
        ->filter((_, val: plug.Plugin) => onlyPlugins->index(val.name) > -1)
    endif

    this._remainingJobs = this._processedPlugins->len()

    if this._remainingJobs ==? 0
      echo 'Nothing to update.'
      return
    endif

    this._updateRan = 1
    this._postRunOpts = opts
    this._commandType = 'update'

    this._OpenBuffer()

    if core.HAS_TIMERS
      this._timer = timer_start(100, (timer) => this._Render(), { repeat: -1 })
    else
      this._RenderIfNoTimers()
    endif

    for plugin in this._processedPlugins
      plugin.Queue()

      this._StartJob(
        plugin.Command(this._depth),
        {
          exit_handler: this._ExitHandler,
          handler: this._StdoutHandler,
          limit_jobs: true,
          plugin: plugin,
        }
      )
    endfor
  enddef

  def Clean()
    var folders = glob(printf('%s%s*%s*', this._dir, core.SLASH, core.SLASH), 0, 1)
    this._processedPlugins = this._plugins->values()

    var plugins: list<string> = []

    for plugin in this._processedPlugins
      plugins->add(plugin.dir)

      if !plugin.rtpDir->empty()
        plugins->add(plugin.rtpDir)
      endif
    endfor

    var toClean = folders
      ->copy()
      ->filter((_, val) => plugins->index(val) < 0)

    if toClean->len() <=? 0
      echo 'Already clean.'
      return
    endif

    this._OpenBuffer()

    var content = ['Clean up', '']
    var lines: dict<number> = {}
    var index = 3

    for item in toClean
      content->add(status.Set('waiting', item, 'Waiting for confirmation…'))

      lines[item] = index
      index += 1
    endfor

    core.Setline(1, content)

    var selected = core.ConfirmWithOptions(
      toClean->len() == 1 ? 'Remove folder?' : 'Remove folders?',
      "&Yes\n&No\n&Ask for each folder"
    )

    if selected ==? 0 || selected ==? 2
      this.Quit()
      return
    endif

    for item in toClean
      var line = lines[item]

      if selected ==? 3
        if !core.Confirm(printf("Remove '%s'?", item))
          core.Setline(line, status.SetOk(item, 'Skipped.'))
          continue
        endif
      endif

      if item->delete('rf') !=? 0
        core.Setline(line, status.SetError(item, 'Failed.'))
      else
        core.Setline(line, status.SetOk(item, 'Removed!'))
      endif
    endfor

    setlocal nomodifiable
  enddef

  def Status()
    if this._IsRunning()
      echo 'Install/Update process still in progress. Please wait until it finishes to view the status.'
      return
    endif

    var result: list<string> = []

    if this._installRan
      this._processedPlugins = this._plugins
        ->values()
        ->filter((_, val: plug.Plugin) => val.installedNow == true)
    elseif this._updateRan
      this._processedPlugins = this._plugins
        ->values()
        ->filter((_, val: plug.Plugin) => val.updated == true)
    else
      this._processedPlugins = this._plugins->values()
    endif

    var hasErrors = false

    for plugin in this._processedPlugins
      var lines = plugin.GetContentForStatus()

      for line in lines
        result->add(line)
      endfor

      if !plugin.installed || plugin.updateFailed || plugin.hookFailed
        hasErrors = true
      endif
    endfor

    this._OpenBuffer()

    var content = ['Plugin status:', ''] + result +
      ['', core.PREVIEW_COMMIT, core.PLUGIN_DETAILS]

    if hasErrors
      content->add(core.VIEW_ERRORS)
    endif

    content->add(core.QUIT_BUFFER)

    core.Setline(1, content)
    setlocal nomodifiable
  enddef

  def Quit()
    if this._IsRunning()
      if !core.Confirm('Installation is in progress. Are you sure you want to quit?')
        return
      endif
    endif

    silent! timer_stop(this._timer)
    silent execute ':q!'
  enddef

  def OpenSha()
    var sha = matchstr(getline('.'), '^\s\s\*\s\zs[0-9a-f]\{7,9}')

    if sha->empty()
      return
    endif

    var pluginName = this._FindPluginBySha(sha)

    if pluginName->empty()
      return
    endif

    silent execute 'pedit' sha
    wincmd p
    setlocal previewwindow filetype=git buftype=nofile nobuflisted modifiable

    var plugin = this._plugins[pluginName]
    var content = git.Show(sha, { dir: plugin.dir })

    setline(1, content)
    setlocal nomodifiable
    cursor(1, 1)
    nnoremap <silent><buffer> q :q<CR>
  enddef

  def OpenOutput(isHook: bool = false)
    var name = core.Trim(matchstr(getline('.'), '^.\s\zs[^—]*\ze'))
    if !this._plugins->has_key(name)
      return
    endif

    var content = this._plugins[name].GetStdoutMessages()

    if content->empty()
      echo 'No output content to show.'
      return
    endif

    silent execute 'pedit' name
    wincmd p
    setlocal previewwindow filetype=sh buftype=nofile nobuflisted modifiable
    silent :1,$delete _
    setline(1, content)
    setlocal nomodifiable
    cursor(1, 1)
    nnoremap <silent><buffer> q :q<CR>
  enddef

  def GotoPlugin(dir: string): number
    return search(printf('^[%s]\s.*$', status.ICONS_STR), dir ==# 'previous' ? 'b' : '')
  enddef

  def OpenPluginDetails()
    var name = core.Trim(matchstr(getline('.'), '^.\s\zs[^—]*\ze'))

    if !this._plugins->has_key(name)
      return
    endif

    var plugin = this._plugins[name]

    silent execute 'pedit' plugin.name
    wincmd p
    setlocal previewwindow buftype=nofile nobuflisted modifiable filetype=
    silent :1,$delete _

    var loadType = plugin.type ==# 'start' ? 'Automatic' : 'Manual'
    var branch = (plugin.branch->empty() ? plugin.GetMainBranch() : plugin.branch)

    var content = [
      'Plugin details:',
      '',
      $'Name:         {plugin.name}',
      $'Loading type: {loadType}',
      $'Directory:    {plugin.dir}',
      $'Url:          {plugin.url}',
      $'Branch:       {branch}',
    ]

    if !plugin.tag->empty()
      content->add($'Tag:          {plugin.tag}')
    endif

    if !plugin.commit->empty()
      content->add($'Commit:       {plugin.commit}')
    endif

    if !plugin.do->empty() && plugin.do->type() ==# v:t_string
      content->extend(['', 'Post Install Command:', $'    {plugin.do}'])
    endif

    if plugin.frozen
      content->extend(['', 'Plugin is frozen, no updates are executed for it.'])
    endif

    setline(1, content)
    setlocal nomodifiable
    cursor(1, 1)
    nnoremap <silent><buffer> q :q<CR>
  enddef

  def GetPlugins(): list<plug.Info>
    return this._plugins
      ->values()
      ->map((_, plugin) => plugin.GetInfo())
  enddef

  def GetPluginNames(): list<string>
    return this._plugins->keys()
  enddef

  def GetPlugin(name: string): plug.Info
    var pluginName = this._pluginNames->get(name, name)

    if !this._plugins->has_key(pluginName)
      throw $'No plugin named {name}'
    endif

    return this._plugins[pluginName].GetInfo()
  enddef

  def HasPlugin(name: string): bool
    var pluginName = this._pluginNames->get(name, name)

    return this._plugins->has_key(pluginName)
  enddef

  def IsPluginInstalled(name: string): bool
    var pluginName = this._pluginNames->get(name, name)

    return this._plugins->has_key(pluginName) && this._plugins[pluginName].installed
  enddef

  def _SavePlugin(pluginConfig: Opts)
    pluginConfig.default_type = this._defaultPluginType
    pluginConfig.dir = this._dir
    pluginConfig.add_required = this.AddRequired

    var plugin = plug.Plugin.new(pluginConfig)

    if this._plugins->has_key(plugin.name)
      return
    endif

    var pluginUrl = plugin.url

    this._plugins[plugin.name] = plugin

    if !this._plugins->has_key(pluginUrl)
      this._pluginNames[pluginUrl] = plugin.name
    endif

    pluginUrl = pluginUrl->substitute('^https://github.com/', '', '')

    if !this._plugins->has_key(pluginUrl)
    this._pluginNames[pluginUrl] = plugin.name
    endif
  enddef

  def _FindPluginBySha(sha: string): string
    var sha_re = printf('^%s', sha)

    for plugin in this._processedPlugins
      var commits = plugin.lastUpdate
        ->copy()
        ->filter((_, val) => val =~? sha_re)

      if commits->len() > 0
        return plugin.name
      endif
    endfor

    return ''
  enddef

  def _UpdateRunningJobs()
    this._remainingJobs -= 1
    this._remainingJobs = max([0, this._remainingJobs]) # Make sure it's not negative
    this._runningJobs -= 1
    this._runningJobs = max([0, this._runningJobs]) # Make sure it's not negative

    this._RenderIfNoTimers()
  enddef

  def _RunPostUpdateHooks()
    if this._postRunHooksCalled == true
      return
    endif

    this._postRunHooksCalled = true

    this._UpdateRemotePluginsAndHelptags()
    this._RenderIfNoTimers(true)

    if this._postRunOpts->has_key('on_finish')
      silent! execute 'redraw'
      execute this._postRunOpts.on_finish
    endif
  enddef

  def _OpenBuffer()
    var buf = bufnr(core.BUFFER)

    if buf > -1
      silent! execute $'buffer {buf}'
      set modifiable
      silent :1,$delete _
    else
      execute $'{this._windowCmd} {core.BUFFER}'
    endif

    execute $'setfiletype {core.FILETYPE}'
    setlocal buftype=nofile bufhidden=wipe nobuflisted nolist noswapfile
    setlocal nowrap cursorline nospell

    syntax clear

    syntax match packixCheck /^✓/
    silent! execute $'syntax match packixPlus /^[+{status.ICONS.progress}]/'
    silent! execute $'syntax match packixPlusText /\(^[+{status.ICONS.progress}]\s\)\@<=[^ —]*/'
    syntax match packixX /^✗/
    syntax match packixStar /^\s\s\*/
    silent! execute $'syntax match packixStatus /\(^[+{status.ICONS.progress}].*—\)\@<=\s.*$/'
    syntax match packixStatusSuccess /\(^✓.*—\)\@<=\s.*$/
    syntax match packixStatusError /\(^✗.*—\)\@<=\s.*$/
    syntax match packixStatusCommit /\(^\*.*—\)\@<=\s.*$/
    syntax match packixSha /\(\*\s\)\@<=[0-9a-f]\{4,}/
    syntax match packixRelDate /([^)]*)$/
    syntax match packixProgress /\(\[\)\@<=[\=]*/

    hi def link packixPlus           Special
    hi def link packixPlusText       String
    hi def link packixCheck          Function
    hi def link packixX              WarningMsg
    hi def link packixStar           Boolean
    hi def link packixStatus         Constant
    hi def link packixStatusCommit   Constant
    hi def link packixStatusSuccess  Function
    hi def link packixStatusError    WarningMsg
    hi def link packixSha            Identifier
    hi def link packixRelDate        Comment
    hi def link packixProgress       Boolean

    this._AddMappings()
  enddef

  def _GetTopStatus(): list<string>
    const BAR_LENGTH = 50.0
    var total = (this._processedPlugins)->len()
    var installed = total - this._remainingJobs
    var bar_installed = float2nr(floor(BAR_LENGTH / total * installed))
    var bar_left = float2nr(BAR_LENGTH - bar_installed)
    var bar = printf('[%s%s]', repeat('=', bar_installed), repeat('-', bar_left))
    var text = this._remainingJobs > 0 ? 'Installing' : 'Installed'
    var finished = this._remainingJobs > 0 ? '' :
      $' - Finished after {split(reltimestr(reltime(this._startTime)))[0]} sec!'

    return [
      printf('%s plugins %d / %d%s', text, installed, total, finished),
      bar,
      ''
    ]
  enddef

  def _RenderIfNoTimers(force: bool = false)
    if core.HAS_TIMERS
      return
    endif

    var ms = str2nr(
      split(split(reltimestr(reltime(this._lastRenderTime)))[0], '\.')[1]
    ) / 1000

    if ms < 100 && !force
      return
    endif

    this._Render()
  enddef

  def _Render()
    var content = this._GetTopStatus()

    for plugin in this._processedPlugins
      if !plugin.state->empty()
        content->add(status.Set(plugin.state, plugin.name, plugin.stateMessage))
      endif
    endfor

    if this._postRunHooksCalled
      content += [
        '',
        core.NAVIGATE_PLUGINS,
        core.PLUGIN_UPDATES,
        core.PLUGIN_DETAILS,
        core.PREVIEW_COMMIT,
        core.QUIT_BUFFER,
      ]
    endif

    var buf = bufnr(core.BUFFER)

    setbufline(buf, 1, content)

    this._lastRenderTime = reltime()

    if this._postRunHooksCalled
      setbufvar(buf, '&modifiable', 0)

      silent! timer_stop(this._timer)
    endif
  enddef

  def _UpdateRemotePluginsAndHelptags()
    for plugin in this._processedPlugins
      if plugin.updated
        silent! execute 'helptags' printf('%s%sdoc', plugin.dir, core.SLASH)->fnameescape()
      endif
    endfor
  enddef

  def _StartJob(cmd: any, opts: Opts)
    if cmd->type() != v:t_string && cmd->type() != v:t_list
      throw 'Invalid command type, it must be a string or list<string>'
    endif

    if opts->has_key('limit_jobs') && this._jobsLimit > 0
      if this._runningJobs > this._jobsLimit
        while this._runningJobs > this._jobsLimit
          silent execute 'redraw'
          sleep 100m
        endwhile
      endif

      this._runningJobs += 1
    endif

    var Ref = function(opts.handler, [opts.plugin])
    var ExitRef = function(opts.exit_handler, [opts.plugin])
    var jobOpts: Opts = { on_stdout: Ref, on_stderr: Ref, on_exit: ExitRef }

    if opts->has_key('cwd')
      jobOpts.cwd = opts.cwd
    endif

    core.WithShell(() => jobsManager.Start(cmd, jobOpts))
  enddef

  def _IsRunning(): bool
    return this._remainingJobs > 0
  enddef

  def _AddMappings()
    if !this._enableDefaultMappings
      return
    endif

    if !hasmapto('<Plug>(PackixQuit)')
      silent! nmap <silent><buffer> q <Plug>(PackixQuit)
    endif

    if !hasmapto('<Plug>(PackixOpenSha)')
      silent! nmap <silent><buffer> <CR> <Plug>(PackixOpenSha)
    endif

    if !hasmapto('<Plug>(PackixOpenOutput)')
      silent! nmap <silent><buffer> E <Plug>(PackixOpenOutput)
    endif

    if !hasmapto('<Plug>(PackixGotoNextPlugin)')
      silent! nmap <silent><buffer> <C-j> <Plug>(PackixGotoNextPlugin)
    endif

    if !hasmapto('<Plug>(PackixGotoPrevPlugin)')
      silent! nmap <silent><buffer> <C-k> <Plug>(PackixGotoPrevPlugin)
    endif

    if !hasmapto('<Plug>(PackixStatus)')
      silent! nmap <silent><buffer> D <Plug>(PackixStatus)
    endif

    if !hasmapto('<Plug>(PackixPluginDetails)')
      silent! nmap <silent><buffer> O <Plug>(PackixPluginDetails)
    endif
  enddef

  def _RunHooksIfFinished()
    if this._remainingJobs <=? 0
      this._RunPostUpdateHooks()
    endif
  enddef

  def _ExitHandler(plugin: plug.Plugin, _jobId: number, jobStatus: number, _event: string)
    this._RenderIfNoTimers()

    if jobStatus != 0
      this._UpdateRunningJobs()
      plugin.SetUpdateFailed()

      var error = plugin.GetShortErrorMessage()
      error = error->empty() ? '' : printf(' - %s', error)

      plugin.SetState('error', printf('Error (exit status %d)%s', jobStatus, error))
      this._RunHooksIfFinished()

      return
    endif

    var text = plugin.UpdateInstallStatus()
    var forceHooks = this._postRunOpts->get('force_hooks', false)
    var Hook = plugin.do

    if !Hook->empty() && (plugin.updated || forceHooks)
      plug.Load(plugin)

      plugin.SetState('progress', 'Running post update hooks…')

      if Hook->type() == v:t_func
        try
          Hook(plugin)
          plugin.SetState('ok', 'Finished running post update hook!')
        catch
          plugin.SetState('error', printf('Error on hook - %s', v:exception))
        endtry

        this._UpdateRunningJobs()
      elseif Hook[0] == ':'
        try
          execute Hook[1 : ]
          plugin.SetState('ok', 'Finished running post update hook!')
        catch
          plugin.SetState('error', printf('Error on hook - %s', v:exception))
        endtry
        this._UpdateRunningJobs()
      else
        this._StartJob(Hook,
          {
            cwd: plugin.dir,
            exit_handler: this._HookExitHandler,
            handler: this._HookStdoutHandler,
            plugin: plugin,
          }
        )
      endif
    else
      plugin.SetState('ok', text)
      this._UpdateRunningJobs()
    endif

    this._RunHooksIfFinished()
  enddef

  def _StdoutHandler(plugin: plug.Plugin, _jobId: number, message: list<string>, event: string)
    plugin.LogEventMessages(message)

    this._RenderIfNoTimers()
    plugin.SetState('progress', plugin.GetLastEventMessage())

    this._RunHooksIfFinished()
  enddef

  def _HookExitHandler(plugin: plug.Plugin, _jobId: number, jobStatus: number, _event: string)
    this._RenderIfNoTimers()
    this._UpdateRunningJobs()

    if jobStatus == 0
      plugin.SetState('ok', 'Finished running post update hook!')
    else
      var error = plugin.GetShortHookErrorMessage()
      error = !error->empty() ? printf(' - %s', error) : ''

      plugin.SetHookFailed()
      plugin.SetState('error', printf('Error on hook (exit status %d)%s', jobStatus, error))
    endif

    this._RunHooksIfFinished()
  enddef

  def _HookStdoutHandler(plugin: plug.Plugin, _jobId: number, message: list<string>, event: string)
    this._RenderIfNoTimers()

    plugin.LogHookEventMessages(message)
    plugin.SetState('progress', plugin.GetLastHookEventMessage())
  enddef
endclass

# --- Implementation

final jobsManager = jobs.Manager.new()

var SetupCallback: func
var SetupOpts: Opts
var Instance: Packix

export def Setup(Callback: any, opts: Opts = {})
  if Callback->empty()
    throw 'Provide valid callback to packix setup via string or funcref.'
  endif

  if Callback->type() == v:t_func
    SetupCallback = Callback
  elseif Callback->type() == v:t_string
    if !exists($'*{Callback}')
      throw $'Function {Callback} does not exist for packix setup. Try' ..
        ' providing a function or funcref.'
    endif

    SetupCallback = funcref(Callback)
  else
    throw 'packix.Setup callback must be a string or a funcref/function.'
  endif

  SetupOpts = opts

  command! -nargs=* -bar PackixInstall call <SID>RunCommand('install', <args>)
  command! -nargs=* -bar PackixUpdate call <SID>RunCommand('update', <args>)
  command! -bar PackixClean call <SID>RunCommand('clean')
  command! -bar PackixStatus call <SID>RunCommand('status')
enddef

export def Init(opts: Opts = {})
  Instance = Packix.new(opts)
enddef

export def Add(url: string, opts: Opts = {})
EnsureInstance().Add(url, opts)
enddef

export def Local(path: string, opts: Opts = {})
  EnsureInstance().Local(path, opts)
enddef

export def Install(opts: Opts = {})
  EnsureInstance().Install(opts)
enddef

export def Update(opts: Opts = {})
  EnsureInstance().Update(opts)
enddef

export def Clean()
  EnsureInstance().Clean()
enddef

export def Status()
  EnsureInstance().Status()
enddef

export def Plugins(): list<plug.Info>
  return EnsureInstance().GetPlugins()
enddef

export def PluginNames(): list<string>
  return EnsureInstance().GetPluginNames()
enddef

export def GetPlugin(name: string): plug.Info
  return EnsureInstance().GetPlugin(name)
enddef

export def HasPlugin(name: string): bool
  return EnsureInstance().HasPlugin(name)
enddef

export def IsPluginInstalled(name: string): bool
  return EnsureInstance().IsPluginInstalled(name)
enddef

export def Version(): string
  return Packix.VERSION
enddef

def RunCommand(cmd: string, opts: any = null)
  EnsureInstance()

  if cmd ==# 'install'
    Install(opts == null ? {} : opts)
  elseif cmd ==# 'update'
    Update(opts == null ? {} : opts)
  elseif cmd ==# 'clean'
    Clean()
  elseif cmd ==# 'status'
    Status()
  endif
enddef

def RunMethod(method: string, direction: string = '')
  EnsureInstance()

  if method ==# 'quit'
    Instance.Quit()
  elseif method ==# 'open_sha'
    Instance.OpenSha()
  elseif method ==# 'open_stdout'
    Instance.OpenOutput()
  elseif method ==# 'goto_plugin'
    Instance.GotoPlugin(direction)
  elseif method ==# 'status'
    Instance.Status()
  elseif method ==# 'open_plugin_details'
    Instance.OpenPluginDetails()
  endif
enddef

nnoremap <silent> <Plug>(PackixQuit) <ScriptCmd>RunMethod('quit')<CR>
nnoremap <silent> <Plug>(PackixOpenSha) <ScriptCmd>RunMethod('open_sha')<CR>
nnoremap <silent> <Plug>(PackixOpenOutput) <ScriptCmd>RunMethod('open_stdout')<CR>
nnoremap <silent> <Plug>(PackixGotoNextPlugin) <ScriptCmd>RunMethod('goto_plugin', 'next')<CR>
nnoremap <silent> <Plug>(PackixGotoPrevPlugin) <ScriptCmd>RunMethod('goto_plugin', 'previous')<CR>
nnoremap <silent> <Plug>(PackixStatus) <ScriptCmd>RunMethod('status')<CR>
nnoremap <silent> <Plug>(PackixPluginDetails) <ScriptCmd>RunMethod('open_plugin_details')<CR>

def EnsureInstance(): Packix
  if Instance == null
    if SetupCallback != null && SetupOpts != null
      Init(SetupOpts)
      SetupCallback(Instance)
    else
      throw 'packix must be initialized before use; see packix.Init or packix.Setup'
    endif
  endif

  return Instance
enddef
