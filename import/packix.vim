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

const MSG_NAVIGATE_PLUGINS = "Use <C-j> and <C-k> to navigate between plugins."
const MSG_PLUGIN_UPDATES = "Press 'D' on an updated plugin to preview the latest updates."
const MSG_PLUGIN_DETAILS = "Press 'O' on a plugin to preview plugin details."
const MSG_PREVIEW_COMMIT = "Press 'Enter' on commit lines to preview the commit."
const MSG_QUIT_BUFFER = "Press 'q' to quit this buffer."
const MSG_VIEW_ERRORS = "Press 'E' on plugins with errors to view output."

class Progress
  static const ICONS = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
  static var _counter: number = 0

  static def Next(): string
    var icon = ICONS[_counter]

    _counter += 1

    if _counter >= len(ICONS)
      _counter = 0
    endif

    return icon
  enddef
endclass

const HAS_SETBUFLINE = has('*setbufline')
const HAS_TIMERS = has('timers')
const IS_WINDOWS = has('win32')

const ICONS = { ok: '✓', error: '✗', waiting: '+', progress: join(Progress.ICONS, '') }
const ICONS_STR = ICONS->values()->join('')
const SLASH = exists('+shellslash') && !&shellslash ? '\' : '/'

const DEFAULT_DIR = printf(
  '%s%s%s',
  substitute(split(&packpath, ',')[0], '\(\\\|\/\)', SLASH, 'g'),
  SLASH, 'pack' .. SLASH .. 'packix'
)
const DEFAULT_DEPTH = 5
const DEFAULT_JOBS = 8
const DEFAULT_WINDOW_CMD = 'vertical topleft new'
const DEFAULT_PLUGIN_TYPE = 'start'
const DISABLE_DEFAULT_MAPPINGS = false

const PACKIX_BUFFER = '__packix__'
const PACKIX_FILETYPE = 'packix'

# --- Utility Functions

def WithShell(Fn: func(): any): any
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

def System(cmd: any): list<string>
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

  const list = message->type() == v:t_string ? [message] : message

  for msg in list
    opts.out->add(msg)
  endfor

  return opts
enddef

def SystemAsync(cmd: any, Callback: func, opts: Opts = {})
  var Ref = function(AsyncOnStdout, [Callback, { out: [] }])

  var jobOpts = { on_stdout: Ref, on_stderr: Ref, on_exit: Ref, }
  var job = WithShell(() => jobs.Start(cmd, jobOpts))

  if job <= 0
    Callback([])
  endif
enddef

def GitVersion(): list<number>
  var result = System('git --version')->get(0, '')

  if result->empty()
    return []
  endif

  var components = result->split('\D\+')

  if components->empty()
    return []
  endif

  var parts: list<number> = []

  for part in components
    parts->add(part->str2nr())
  endfor

  return parts
enddef

def StatusOk(name: string, text: string): string
  return StatusString('ok', name, text)
enddef

def StatusProgress(name: string, text: string): string
  return StatusString('progress', name, text)
enddef

def StatusError(name: string, text: string): string
  return StatusString('error', name, text)
enddef

def StatusString(type: string, name: string, text: string): string
  return printf(
    '%s %s — %s',
    type ==? 'progress' ? Progress.Next() : ICONS[type],
    name,
    text
  )
enddef

def Confirm(question: string): bool
  return ConfirmWithOptions(question, "&Yes\nNo") ==? 1
enddef

def ConfirmWithOptions(question: string, options: string): number
  silent! exec 'redraw'

  try
    return question->confirm(options)
  catch
    return 0
  endtry
enddef

def Trim(str: string): string
  return str->substitute('^\s*\(.\{-}\)\s*$', '\1', '')
enddef

def Setline(line: number, content: any)
  if content->type() != v:t_string && content->type() != v:t_list
    throw 'Invalid content type, must be a string or list<string>'
  endif

  var window = bufwinnr(PACKIX_BUFFER)

  if window < 0
    return
  endif

  if winnr() !=? window
    silent! exec ':' .. window .. 'wincmd w'
  endif

  setline(line, content)
enddef

def SymlinkCommand(src: string, dest: string): string
  if executable('ln')
    return printf('ln -sf %s %s', shellescape(src), shellescape(dest))
  endif

  if has('win32') && executable('mklink')
    return printf('mklink %s %s', shellescape(src), shellescape(dest))
  endif

  return null_string
enddef

# --- Implementation

class JobInfo
  var job: job
  var opts: Opts
  var channel: channel
  public var buffer: string = ''

  def new(job: job, opts: Opts)
    this.opts = opts
    this.job = job
    this.channel = job->job_getchannel()
  enddef
endclass

class JobManager
  var _jobs: dict<JobInfo>
  var _jobIdSeq: number

  def new()
    this._jobs = {}
    this._jobIdSeq = 0
  enddef

  def Start(cmd: any, opts: Opts): number
    if cmd->type() != v:t_string && cmd->type() != v:t_list
      throw 'Invalid command type, it must be a string or list<string>'
    endif

    var jobId = this._NextJobId()

    var jobCmd = cmd->type() == v:t_list ? join(cmd, ' ') : cmd
    jobCmd = printf('%s %s "%s"', &shell, &shellcmdflag, jobCmd)

    var jobOpt: Opts = {
      out_cb: function(this._StdoutCallback, [jobId, opts]),
      err_cb: function(this._StderrCallback, [jobId, opts]),
      exit_cb: function(this._ExitCallback, [jobId, opts]),
    }

    if opts->has_key('cwd')
      jobOpt.cwd = opts.cwd
    endif

    if opts->has_key('env')
      jobOpt.env = opts.env
    endif

    jobOpt.mode = 'raw'
    jobOpt.noblock = 1

    var job = jobCmd->job_start(jobOpt)

    if job->job_status() !=? 'run'
      return -1
    endif

    this._jobs[jobId] = JobInfo.new(job, opts)

    return jobId
  enddef

  def Remove(jobId: number)
    if this._jobs->has_key(jobId)
      this._jobs->remove(jobId)
    endif
  enddef

  # Currently unused
  def Stop(jobId: number)
    if this._jobs->has_key(jobId)
      var info: JobInfo = this._jobs[jobId]

      if info->type(.job) == v:t_job
        info.job->job_stop()
      elseif info->type(.job) == v:t_channel
        info.job->ch_close()
      endif
    endif
  enddef

  # Currently unused
  def Send(jobId: number, data: string, opts: Opts)
    if this._jobs->has_key(jobId)
      var info: JobInfo = this._jobs[jobId]
      var close_stdin = opts->get('close_stdin', 0) > 0

      # There is no easy way to know when ch_sendraw() finishes writing data
      # on a non-blocking channels -- has('patch-8.1.889') -- and because of
      # this, we cannot safely call ch_close_in().  So when we find ourselves
      # in this situation (i.e. noblock=1 and close stdin after send) we fall
      # back to using FlushVimSendraw() and wait for transmit buffer to be
      # empty
      #
      # Ref: https://groups.google.com/d/topic/vim_dev/UNNulkqb60k/discussion

      if !close_stdin
        info.channel->ch_sendraw(data)
      else
        info.buffer ..= data

        this._FlushVimSendraw(jobId, null)
      endif

      if close_stdin
        while len(info.buffer) != 0
          sleep 1m
        endwhile

        ch_close_in(info.channel)
      endif
    endif
  enddef

  # Currently unused
  def WaitOne(jobId: number, timeout: number, start: list<any>): number
    if !this._jobs->has_key(jobId)
      return -3
    endif

    var info = this._jobs[jobId]

    var _timeout = timeout / 1000.0

    try
      while _timeout < 0 || reltimefloat(reltime(start)) < _timeout
        var jobInfo = info.job->job_info()

        if jobInfo.status ==# 'dead'
          return jobInfo.exitval
        elseif jobInfo.status ==# 'fail'
          return -3
        endif

        sleep 1m
      endwhile
    catch /^Vim:Interrupt$/
      return -2
    endtry

    return -1
  enddef

  # Currently unused
  def Wait(jobIds: list<number>, timeout: number): list<number>
    var start = reltime()
    var exitcode = 0
    var ret: list<number> = []

    for jobId in jobIds
      if exitcode != -2 # Not interrupted
        exitcode = this.WaitOne(jobId, timeout, start)
      endif

      ret += [exitcode]
    endfor

    return ret
  enddef

  # Currently unused
  def Pid(jobId: number): number
    if !this._jobs->has_key(jobId)
      return 0
    endif

    var info = this._jobs[jobId]
    var jobInfo = info.job->job_info()

    if jobInfo->type() == v:t_dict && jobInfo->has_key('process')
      return jobInfo.process
    endif

    return 0
  enddef

  def _NextJobId(): number
    this._jobIdSeq += 1
    return this._jobIdSeq
  enddef

  def _StdoutCallback(jobId: number, opts: Opts, job: any, data: string)
    if opts->has_key('on_stdout')
      opts.on_stdout(jobId, split(data, "\n", 1), 'stdout')
    endif
  enddef

  def _StderrCallback(jobId: number, opts: Opts, job: any, data: string)
    if opts->has_key('on_stderr')
      opts.on_stderr(jobId, split(data, "\n", 1), 'stderr')
    endif
  enddef

  def _ExitCallback(jobId: number, opts: Opts, job: any, status: number)
    if opts->has_key('on_exit')
      opts.on_exit(jobId, status, 'exit')
    endif

    this.Remove(jobId)
  enddef

  def _FlushVimSendraw(jobId: number, timerId: number = null)
    # https://github.com/vim/vim/issues/2548
    # https://github.com/natebosch/vim-lsc/issues/67#issuecomment-357469091

    if !this._jobs->has_key(jobId)
      return
    endif

    var info = this._jobs[jobId]

    if info != null
      sleep 1m

      if info.buffer->len() <= 4096
        info.channel->ch_sendraw(info.buffer)
        info.buffer = ''
      else
        var toSend = info.buffer[:4095]
        info.buffer = info.buffer[4096:]

        info.channel->ch_sendraw(toSend)
        timer_start(1, function(this._FlushVimSendraw, [jobId]))
      endif
    endif
  enddef
endclass

interface IManager
  def AddRequired(name: string, requiredPackage: any)
  def DefaultPluginType(): string
  def Dir(): string
  def SupportsSubmoduleProgress(): bool
endinterface

class PluginInfo
  var name: string
  var type: string
  var url: string
  var dir: string
  var rev: string
  var headRef: string
  var installed: bool
  var isLocal: bool
  var mainBranch: string
  var rtpDir: string
endclass

class Plugin
  var name: string
  var dir: string

  var branch: string
  var commit: string
  var tag: string
  var rtp: string
  var rtpDir: string = ''
  var type: string
  var url: string
  var frozen: bool
  var local: bool

  var rev: string
  var installed: bool
  var updated: bool = false
  var updateFailed: bool = false
  var installedNow: bool = false
  var hookFailed: bool = false
  var lastUpdate: list<string> = []

  var status: string = ''
  var statusMessage: string = ''
  var headRef: string = ''
  var mainBranch: string = ''

  var do: any
  var requires: any

  var _packix: IManager

  var _eventMessages: list<string> = []
  var _hookEventMessages: list<string> = []

  def new(name: string, opts: Opts, packix: IManager)
    this.type = opts->get('type', packix.DefaultPluginType())
    this._packix = packix

    this.branch = opts->get('branch', '')
    this.commit = opts->get('commit', '')
    this.tag = opts->get('tag', '')
    this.frozen = opts->get('frozen', false)
    this.do = opts->get('do', '')
    this.local = opts->get('local', false)
    this.requires = opts->get('requires')

    if ['opt', 'start']->index(this.type) < 0
      this.type = 'start'
    endif

    this.name = opts->get('name')->empty() ? name->split('/')[-1] : opts.name
    this.dir = printf('%s%s%s%s%s', packix.Dir(), SLASH, this.type, SLASH, this.name)

    this.rtp = opts->get('rtp', '')

    if !this.rtp->empty()
      var rtp = this.rtp
        ->substitute('[\\\/]$', '', '')
        ->substitute('[\\\/]', '__', 'g')

      this.rtpDir = printf('%s__%s', this.dir, rtp)
    endif

    this.url = name =~? '^\(http\|git@\).*' ? name :
      this.local ? name : printf('https://github.com/%s', name)

    if this.dir->isdirectory()
      this.installed = true

      if IS_WINDOWS
        this._UpdateRevisionAsync()
        this._UpdateHeadRefAsync()
        this._UpdateMainBranchAsync()
      endif
    endif

    if !this.requires->empty() && this.requires->type() != v:t_list
      this.requires = [this.requires]
    endif

    if !this.requires->empty()
      for require in this.requires
        this._packix.AddRequired(this.name, require)
      endfor
    endif
  enddef

  def SetUpdateFailed()
    this.updateFailed = true
  enddef

  def SetHookFailed()
    this.hookFailed = true
  enddef

  def GetInfo(): PluginInfo
    if !IS_WINDOWS
      this._UpdateRevision()
      this._UpdateHeadRef()
      this._UpdateMainBranch()
    endif

    return PluginInfo.new(
      this.name,
      this.type,
      this.url,
      this.dir,
      this.rev,
      this.headRef,
      this.installed,
      this.local,
      this.mainBranch,
      this.rtpDir
    )
  enddef

  def Queue()
    if !IS_WINDOWS
      this._UpdateRevision()
    endif

    this.SetStatus('progress', this.installed ? 'Updating…' : 'Installing…')
  enddef

  def SetStatus(status: string, message: string)
    this.status = status
    this.statusMessage = message
  enddef

  def Command(depth: any): string
    if this.dir->isdirectory() && !this.local
      return this._UpdateGitCommand()
    endif

    if this.local
      return this._LocalCommand()
    endif

    return this._InstallGitCommand(depth)
  enddef

  def GetMainBranch(): string
    return this._UpdateMainBranch()
  enddef

  def UpdateInstallStatus(): string
    if !this.installed
      this.installed = true
      this.updated = true
      this.installedNow = true
      this._SymlinkRtp()
      return 'Installed!'
    endif

    if this._HasUpdates()
      this.updated = true
      this._GetLastUpdate()
      this._SymlinkRtp()
      return 'Updated!'
    endif

    return 'Already up to date.'
  enddef

  def GetLastHookEventMessage(): string
    return this._hookEventMessages->get(-1, '')
  enddef

  def GetLastEventMessage(): string
    return this._eventMessages->get(-1, '')
  enddef

  def LogHookEventMessages(messages: list<string>)
    for message in messages
      var msg = Trim(message)

      if !msg->empty() && this._hookEventMessages->index(msg) < 0
        this._hookEventMessages->add(msg)
      endif
    endfor
  enddef

  def LogEventMessages(messages: list<string>)
    for message in messages
      var msg = Trim(message)

      if !msg->empty() && this._eventMessages->index(msg) < 0
        this._eventMessages->add(msg)
      endif
    endfor
  enddef

  def GetShortHookErrorMessage(): string
    return Trim(this._hookEventMessages->get(-1, ''))
  enddef

  def GetShortErrorMessage(): string
    return Trim(this._eventMessages->get(-1, ''))
  enddef

  def GetStdoutMessages(): list<string>
    var result: list<string> = []

    var messages = this.hookFailed ? this._hookEventMessages : this._eventMessages

    for msg in messages
      for line in msg->split('\r')
        if !Trim(line)->empty()
          result->add(line)
        endif
      endfor
    endfor

    return result
  enddef

  def GetContentForStatus(): list<string>
    if !this.installed
      var error = this.GetShortErrorMessage()
      var last = !error->empty() ? ' Last line of error message:' : ''
      var status = printf('Not installed.%s', last)
      var result = [StatusError(this.name, status)]

      if !error->empty()
        result->add(printf('  * %s', error))
      endif

      return result
    endif

    if this.updateFailed
      return [
        StatusError(this.name, 'Install/update failed. Last line of error message:'),
        printf('  * %s', this.GetShortErrorMessage())
      ]
    endif

    if this.hookFailed
      return [
        StatusError(this.name, 'Post hook failed. Last line of error message:'),
        printf('  * %s', this.GetShortHookErrorMessage())
      ]
    endif

    if this.installedNow
      return [StatusOk(this.name, 'Installed!')]
    endif

    if !this.updated
      this._GetLastUpdate()
    endif

    if this.lastUpdate->empty()
      return [StatusOk(this.name, 'OK.')]
    endif

    var text = this.updated ? 'Updated!' : 'Last update:'
    var result = [StatusOk(this.name, text)]

    for line in this.lastUpdate
      result->add(printf('  * %s', line))
    endfor

    return result
  enddef

  def _FetchRevisionCommand(): string
    return printf('git -C %s rev-parse HEAD', this.dir->shellescape())
  enddef

  def _UpdateRevision()
    this.rev = this._FetchRevision()
  enddef

  def _FetchRevision(): string
    return this._ParseRevision(System(this._FetchRevisionCommand()))
  enddef

  def _UpdateRevisionAsync()
    SystemAsync(
      this._FetchRevisionCommand(),
      (output) => {
        this.rev = this._ParseRevision(output)
      }
    )
  enddef

  def _ParseRevision(output: list<string>): string
    var rev = output->get(0, '')
    return rev =~? '^fatal' ? '' : rev
  enddef

  def _UpdateHeadRefCommand(): string
    return printf('git -C %s rev-parse --abbrev-ref HEAD', this.dir->shellescape())
  enddef

  def _UpdateHeadRef(): string
    if this.headRef->empty()
      this.headRef = this._ParseHeadRef(System(this._UpdateHeadRefCommand()))
    endif

    return this.headRef
  enddef

  def _UpdateHeadRefAsync()
    if !this.headRef->empty()
      return 
    endif

    SystemAsync(
      this._UpdateHeadRefCommand(),
      (output) => {
        this.headRef = this._ParseHeadRef(output)
      }
    )
  enddef

  def _ParseHeadRef(output: list<string>): string
    var headRef = output->get(0, '')
    return headRef =~? '^fatal' ? '' : headRef
  enddef

  def _UpdateMainBranchCommand(): string
    return printf(
      'git -C %s symbolic-ref refs/remotes/origin/HEAD --short',
      this.dir->shellescape()
    )
  enddef

  def _UpdateMainBranch(): string
    if this.mainBranch->empty()
      this.mainBranch = this._ParseMainBranch(System(this._UpdateMainBranchCommand()))
    endif

    return this.mainBranch
  enddef

  def _UpdateMainBranchAsync()
    if !this.mainBranch->empty()
      return
    endif

    SystemAsync(
      this._UpdateMainBranchCommand(),
      (output) => {
        this.mainBranch = this._ParseMainBranch(output)
      }
    )
  enddef

  def _ParseMainBranch(output: list<string>): string
    var ref = output->get(0, '')
    return ref =~? '^fatal' ? '' : ref->substitute('^origin/', '', '')
  enddef

  def _GitCheckoutTarget(): string
    for target in [this.commit, this.tag, this.branch]
      if !target->empty()
        return target
      endif
    endfor

    return null_string
  enddef

  def _GitCheckoutCommand(target: string): string
    return target->empty() ? '' : printf('git checkout %s', target->shellescape())
  enddef

  def _UpdateGitCommand(): string
    this._UpdateHeadRef()
    this._UpdateMainBranch()

    var target = this._GitCheckoutTarget()
    var checkoutCommand: string
    var isOnBranch = false

    var hasCheckout = !target->empty()

    if target->empty()
      if this.headRef ==? 'HEAD' && !this.mainBranch->empty()
        isOnBranch = true
        checkoutCommand = this._GitCheckoutCommand(this.mainBranch)
      endif
    else
      isOnBranch = target ==? this.branch
      checkoutCommand = this._GitCheckoutCommand(target)
    endif

    var refreshCommand = isOnBranch ?
      'git pull --ff-only --progress --rebase=false' :
      printf('git fetch %s --depth 999999', this.url->shellescape())

    return [
      this._CdCommand(),
      checkoutCommand,
      refreshCommand,
      this._GitUpdateSubmoduleCommand()
    ]->filter((_, v) => !v->empty())->join(' && ')
  enddef

  def _GitCloneCommand(depth: string): string
    var target: string

    if this.commit->empty()
      for candidate in [this.tag, this.branch]
        if !candidate->empty()
          target = candidate
          break
        endif
      endfor
    endif

    target = target->empty() ? '' : printf(' --branch %s', target->shellescape())

    return printf(
      'git clone --progress %s %s --depth %s --no-single-branch%s',
      this.url->shellescape(),
      this.dir->shellescape(),
      depth,
      target
    )
  enddef

  def _CdCommand(): string
    return IS_WINDOWS ?
      printf('cd /d %s', this.dir->shellescape()) :
      printf('cd %s', this.dir->shellescape())
  enddef

  def _GitUpdateSubmoduleCommand(): string
    return printf(
      'git submodule update --init --recursive%s',
      this._packix.SupportsSubmoduleProgress() ? ' --progress' : ''
    )
  enddef

  def _InstallGitCommand(depth: any): string
    return join([
      this._GitCloneCommand(depth->string()),
      this._CdCommand(),
      this._GitUpdateSubmoduleCommand()
    ], ' && ')
  enddef

  def _LocalCommand(): string
    var cmd = SymlinkCommand(this.url->fnamemodify(':p'), this.dir)

    if !cmd->empty()
      return cmd
    endif

    return printf(
      'echo Cannot install %s locally, linking tool not found.', this.name
    )
  enddef

  def _HasUpdates(): bool
    return !this.rev->empty() && this.rev !=? this._FetchRevision()
  enddef

  def _GetLastUpdate()
    var commits = System(printf(
      'git -C %s log --color=never --pretty=format:%s --no-show-signature HEAD@{1}',
      this.dir->shellescape(), shellescape('%h %s (%cr)')
    ))

    this.lastUpdate = commits->filter((_, v) => v !=? '' && v !~? '^fatal')
  enddef

  def _SymlinkRtp()
    if this.rtpDir->empty()
      return
    endif

    var dir = printf('%s/%s', this.dir, this.rtp)
    var cmd = SymlinkCommand(dir, this.rtpDir)

    if !cmd->empty()
      System(cmd)
    endif
  enddef
endclass

def LoadPlugin(wanted: Plugin)
  if &runtimepath->empty()
    &runtimepath = wanted.dir
  else
    &runtimepath ..= printf(',%s', wanted.dir)
  endif

  for path in ['plugin/**/*.vim', 'after/plugin/**/*.vim']
    var full_path = printf('%s/%s', wanted.dir, path)

    if !full_path->glob()->empty()
      silent exec 'source ' .. full_path
    endif
  endfor
enddef

export class Manager implements IManager
  var _commandType: string = ''
  var _depth: number = DEFAULT_DEPTH
  var _disableDefaultMappings: bool = DISABLE_DEFAULT_MAPPINGS
  var _gitVersion: list<number>
  var _installRan: bool = false
  var _jobs: number = DEFAULT_JOBS
  var _lastRenderTime: list<number>
  var _plugins: dict<Plugin> = {}
  var _postRunHooksCalled: bool = false
  var _postRunOpts: Opts = {}
  var _processedPlugins: list<Plugin> = []
  var _remainingJobs: number = 0
  var _result: list<string>
  var _runningJobs: number = 0
  var _startTime: list<number>
  var _timer: number = -1
  var _updateRan: bool = false
  var _window_cmd: string = DEFAULT_WINDOW_CMD
  var _defaultPluginType: string = DEFAULT_PLUGIN_TYPE
  var _dir: string = DEFAULT_DIR

  static const VERSION = '1.0.0'

  def new(opts: Opts)
    if opts->has_key('dir')
      this._dir = opts.dir
        ->fnamemodify(':plugin')
        ->substitute('\' .. SLASH .. '$', '', '')
    endif

    if opts->has_key('depth')
      this._depth = opts.depth
    endif

    if opts->has_key('jobs')
      this._jobs = opts.jobs
    endif

    if opts->has_key('window_cmd')
      this._window_cmd = opts.window_cmd
    endif

    if opts->has_key('default_plugin_type')
      this._defaultPluginType = opts.default_plugin_type
    endif

    if opts->has_key('disable_default_mappings')
      this._disableDefaultMappings = opts.disable_default_mappings
    endif

    this._lastRenderTime = reltime()
    this._gitVersion = GitVersion()

    silent! mkdir(printf('%s%s%s', this._dir, SLASH, 'opt'), 'p')
    silent! mkdir(printf('%s%s%s', this._dir, SLASH, 'start'), 'p')
  enddef

  def DefaultPluginType(): string
    return this._defaultPluginType
  enddef

  def Dir(): string
    return this._dir
  enddef

  def Add(url: string, opts: Opts = {})
    var plugin = Plugin.new(url, opts, this)
    this._plugins[plugin.name] = plugin
  enddef

  def SupportsSubmoduleProgress(): bool
    if this._gitVersion->empty()
      return false
    endif

    return this._gitVersion->get(0, 0) >= 2 &&
      this._gitVersion->get(1, 0) >= 11
  enddef

  def AddRequired(url: string, requiredPackage: any)
    if requiredPackage->type() == v:t_string
      Add(requiredPackage)
      return
    endif

    if requiredPackage->type() != v:t_dict
      throw "'requires' values must be strings or dictionaries"
    endif

    var requiredUrl: string = requiredPackage->get('url', '')
    var requiredOpts: Opts = requiredPackage->get('opts', {})

    if requiredurl->empty()
      throw "Missing 'requires' package url for '" .. url .. "'."
    endif

    var plugin = Plugin.new(requiredUrl, requiredOpts, this)

    if !this._plugins->has_key(plugin.name)
      this._plugins[plugin.name] = plugin
    endif
  enddef

  def Local(path: string, opts: Opts = {})
    opts.local = true
    var plugin = Plugin.new(path, opts, this)
    this._plugins[plugin.name] = plugin
  enddef

  def Install(opts: Opts)
    this._startTime = reltime()
    this._result = []
    this._processedPlugins = this._plugins
      ->values()
      ->filter((_, val: Plugin) => !val.installed)

    var onlyPlugins: list<string> = opts->get('plugins', [])

    if !onlyPlugins->empty()
      this._processedPlugins = this._processedPlugins
        ->filter((_, val: Plugin) => onlyPlugins->index(val.name) > -1)
    endif

    this._remainingJobs = this._processedPlugins->len()

    if this._remainingJobs ==? 0
      echo 'Nothing to install.'
      return
    endif

    this._installRan = true
    this._postRunOpts = opts

    this._OpenBuffer()

    if HAS_TIMERS
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

  def Update(opts: Opts)
    this._startTime = reltime()
    this._result = []
    this._processedPlugins = this._plugins
      ->values()
      ->filter((_, val: Plugin) => val.frozen == false || val.local == false)

    var onlyPlugins: list<string> = opts->get('plugins', [])

    if !onlyPlugins->empty()
      this._processedPlugins = this._processedPlugins
        ->filter((_, val: Plugin) => onlyPlugins->index(val.name) > -1)
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

    if HAS_TIMERS
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
    var folders = glob(printf('%s%s*%s*', this._dir, SLASH, SLASH), 0, 1)
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
      content->add(StatusString('waiting', item, 'Waiting for confirmation…'))

      lines[item] = index
      index += 1
    endfor

    Setline(1, content)

    var selected = ConfirmWithOptions(
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
        if !Confirm(printf("Remove '%s'?", item))
          Setline(line, StatusOk(item, 'Skipped.'))
          continue
        endif
      endif

      if item->delete('rf') !=? 0
        Setline(line, StatusError(item, 'Failed.'))
      else
        Setline(line, StatusOk(item, 'Removed!'))
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
        ->filter((_, val: Plugin) => val.installedNow == true)
    elseif this._updateRan
      this._processedPlugins = this._plugins
        ->values()
        ->filter((_, val: Plugin) => val.updated == true)
    else
      this._processedPlugins = this._plugins->values()
    endif

    var hasErrors = false

    for plugin in this._processedPlugins
      var status = plugin.GetContentForStatus()

      for line in status
        result->add(line)
      endfor

      if !plugin.installed || plugin.updateFailed || plugin.hookFailed
        hasErrors = true
      endif
    endfor

    this._OpenBuffer()

    var content = ['Plugin status:', ''] + result +
      ['', MSG_PREVIEW_COMMIT, MSG_PLUGIN_DETAILS]

    if hasErrors
      content->add(MSG_VIEW_ERRORS)
    endif

    content->add(MSG_QUIT_BUFFER)

    Setline(1, content)
    setlocal nomodifiable
  enddef

  def Quit()
    if this._IsRunning()
      if !Confirm('Installation is in progress. Are you sure you want to quit?')
        return
      endif
    endif

    silent! timer_stop(this._timer)
    silent exec ':q!'
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

    silent exec 'pedit' sha
    wincmd p
    setlocal previewwindow filetype=git buftype=nofile nobuflisted modifiable

    var plugin = this._plugins[pluginName]

    var content = System([
      'git', '-C', plugin.dir->shellescape(), 'show', '--no-color',
      '--pretty=medium', sha->shellescape()
    ])

    setline(1, content)
    setlocal nomodifiable
    cursor(1, 1)
    nnoremap <silent><buffer> q :q<CR>
  enddef

  def OpenOutput(isHook: bool = false)
    var name = Trim(matchstr(getline('.'), '^.\s\zs[^—]*\ze'))
    if !this._plugins->has_key(name)
      return
    endif

    var content = this._plugins[name].GetStdoutMessages()

    if content->empty()
      echo 'No output content to show.'
      return
    endif

    silent exec 'pedit' name
    wincmd p
    setlocal previewwindow filetype=sh buftype=nofile nobuflisted modifiable
    silent :1,$delete _
    setline(1, content)
    setlocal nomodifiable
    cursor(1, 1)
    nnoremap <silent><buffer> q :q<CR>
  enddef

  def GotoPlugin(dir: string): number
    return search(printf('^[%s]\s.*$', ICONS_STR), dir ==? 'previous' ? 'b' : '')
  enddef

  def OpenPluginDetails()
    var name = Trim(matchstr(getline('.'), '^.\s\zs[^—]*\ze'))

    if !this._plugins->has_key(name)
      return
    endif

    var plugin = this._plugins[name]

    silent exec 'pedit' plugin.name
    wincmd p
    setlocal previewwindow buftype=nofile nobuflisted modifiable filetype=
    silent :1,$delete _

    var content = [
      'Plugin details:',
      '',
      'Name:         ' .. plugin.name,
      'Loading type: ' .. (plugin.type ==? 'start' ? 'Automatic' : 'Manual'),
      'Directory:    ' .. plugin.dir,
      'Url:          ' .. plugin.url,
      'Branch:       ' .. (plugin.branch->empty() ? plugin.GetMainBranch() : plugin.branch)
    ]

    if !plugin.tag->empty()
      content->add('Tag:          ' .. plugin.tag)
    endif

    if !plugin.commit->empty()
      content->add('Commit:       ' .. plugin.commit)
    endif

    if !plugin.do->empty() && plugin.do->type() ==? type('')
      content->extend(['', 'Post Install Command:', '    ' .. plugin.do])
    endif

    if plugin.frozen
      content->extend(['', 'Plugin is frozen, no updates are executed for it.'])
    endif

    setline(1, content)
    setlocal nomodifiable
    cursor(1, 1)
    nnoremap <silent><buffer> q :q<CR>
  enddef

  def GetPlugins(): list<PluginInfo>
    return this._plugins
      ->values()
      ->map((_, plugin) => plugin.GetInfo())
  enddef

  def GetPluginNames(): list<string>
    return this._plugins->keys()
  enddef

  def GetPlugin(name: string): PluginInfo
    if !this._plugins->has_key(name)
      throw 'No plugin named ' .. name
    endif

    return this._plugins[name].GetInfo()
  enddef

  def HasPlugin(name: string): bool
    return this._plugins->has_key(name)
  enddef

  def IsPluginInstalled(name: string): bool
    return this._plugins->has_key(name) && this._plugins[name].installed
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
      silent! exec 'redraw'
      exec this._postRunOpts.on_finish
    endif
  enddef

  def _OpenBuffer()
    var buf = bufnr(PACKIX_BUFFER)

    if buf > -1
      silent! exec 'b' .. buf
      set modifiable
      silent :1,$delete _
    else
      exec this._window_cmd PACKIX_BUFFER
    endif

    setfiletype packix
    setlocal buftype=nofile bufhidden=wipe nobuflisted nolist noswapfile nowrap cursorline nospell
    syntax clear

    syntax match packixCheck /^✓/
    silent! exec 'syntax match packixPlus /^[+' .. ICONS.progress .. ']/'
    silent! exec 'syntax match packixPlusText /\(^[+' .. ICONS.progress .. ']\s\)\@<=[^ —]*/'
    syntax match packixX /^✗/
    syntax match packixStar /^\s\s\*/
    silent! exec 'syntax match packixStatus /\(^[+' .. ICONS.progress .. '].*—\)\@<=\s.*$/'
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
      ' - Finished after ' .. split(reltimestr(reltime(this._startTime)))[0] .. ' sec!'

    return [
      printf('%s plugins %d / %d%s', text, installed, total, finished),
      bar,
      ''
    ]
  enddef

  def _RenderIfNoTimers(force: bool = false)
    if HAS_TIMERS
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
      if !plugin.status->empty()
        content->add(StatusString(plugin.status, plugin.name, plugin.statusMessage))
      endif
    endfor

    if this._postRunHooksCalled
      content += [
        '',
        MSG_NAVIGATE_PLUGINS,
        MSG_PLUGIN_UPDATES,
        MSG_PLUGIN_DETAILS,
        MSG_PREVIEW_COMMIT,
        MSG_QUIT_BUFFER,
      ]
    endif

    var buf = bufnr(PACKIX_BUFFER)

    if HAS_SETBUFLINE
      setbufline(buf, 1, content)
    else
      if &filetype !=? PACKIX_FILETYPE
        exec ':' .. bufwinnr(PACKIX_BUFFER) .. 'wincmd w'
      endif

      setline(1, content)
    endif

    this._lastRenderTime = reltime()

    if this._postRunHooksCalled
      if HAS_SETBUFLINE
        setbufvar(buf, '&modifiable', 0)
      else
        setlocal nomodifiable
      endif

      silent! timer_stop(this._timer)
    endif
  enddef

  def _UpdateRemotePluginsAndHelptags()
    for plugin in this._processedPlugins
      if plugin.updated
        silent! exec 'helptags' printf('%s%sdoc', plugin.dir, SLASH)->fnameescape()
      endif
    endfor
  enddef

  def _StartJob(cmd: any, opts: Opts)
    if cmd->type() != v:t_string && cmd->type() != v:t_list
      throw 'Invalid command type, it must be a string or list<string>'
    endif

    if opts->has_key('limit_jobs') && this._jobs > 0
      if this._runningJobs > this._jobs
        while this._runningJobs > this._jobs
          silent exec 'redraw'
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

    WithShell(() => jobs.Start(cmd, jobOpts))
  enddef

  def _IsRunning(): bool
    return this._remainingJobs > 0
  enddef

  def _AddMappings()
    if this._disableDefaultMappings
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

  def _ExitHandler(plugin: Plugin, _jobId: number, status: number, _event: string) 
    this._RenderIfNoTimers()

    if status != 0
      this._UpdateRunningJobs()
      plugin.SetUpdateFailed()

      var error = plugin.GetShortErrorMessage()
      error = error->empty() ? '' : printf(' - %s', error)

      plugin.SetStatus('error', printf('Error (exit status %d)%s', status, error))
      this._RunHooksIfFinished()

      return
    endif

    var text = plugin.UpdateInstallStatus()
    var forceHooks = this._postRunOpts->get('force_hooks', false)
    var Hook = plugin.do

    if !Hook->empty() && (plugin.updated || forceHooks)
      LoadPlugin(plugin)

      plugin.SetStatus('progress', 'Running post update hooks…')

      if Hook->type() == v:t_func
        try
          Hook(plugin)
          plugin.SetStatus('ok', 'Finished running post update hook!')
        catch
          plugin.SetStatus('error', printf('Error on hook - %s', v:exception))
        endtry

        this._UpdateRunningJobs()
      elseif Hook[0] == ':'
        try
          exec Hook[1 : ]
          plugin.SetStatus('ok', 'Finished running post update hook!')
        catch
          plugin.SetStatus('error', printf('Error on hook - %s', v:exception))
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
      plugin.SetStatus('ok', text)
      this._UpdateRunningJobs()
    endif

    this._RunHooksIfFinished()
  enddef

  def _StdoutHandler(plugin: Plugin, _jobId: number, message: list<string>, event: string)
    plugin.LogEventMessages(message)

    this._RenderIfNoTimers()
    plugin.SetStatus('progress', plugin.GetLastEventMessage())

    this._RunHooksIfFinished()
  enddef

  def _HookExitHandler(plugin: Plugin, _jobId: number, status: number, _event: string)
    this._RenderIfNoTimers()
    this._UpdateRunningJobs()

    if status == 0
      plugin.SetStatus('ok', 'Finished running post update hook!')
    else
      var error = plugin.GetShortHookErrorMessage()
      error = !error->empty() ? printf(' - %s', error) : ''

      plugin.SetHookFailed()
      plugin.SetStatus('error', printf('Error on hook (exit status %d)%s', status, error))
    endif

    this._RunHooksIfFinished()
  enddef

  def _HookStdoutHandler(plugin: Plugin, _jobId: number, message: list<string>, event: string)
    this._RenderIfNoTimers()

    plugin.LogHookEventMessages(message)
    plugin.SetStatus('progress', plugin.GetLastHookEventMessage())
  enddef
endclass

final jobs = JobManager.new()
var SetupCallback: func
var SetupOpts: Opts
var Instance: Manager

# Full-featured configuration, including setting up commands :PackixInstall,
# :PackixUpdate, :PackixClean, and :PackixStatus.
#
# The `Callback` must be a function name string, function reference, or lambda
# that accepts a single parameter (the `packix.Manager` instance).
# 
# Initialization options can be provided as an optional second parameter.
#
# ### Examples
#
# With `vim9script`:
#
# ```VimL
# vim9script
# packadd vim-packix
#
# import 'packix.vim'
#
# packix.Setup((px: packix.Manager) =>
#   px.Add('halostatue/vim-packix', { 'type': 'opt' })
#   px.Add('junegunn/fzf', { 'do': './install --all && ln -s $(pwd) ~/.fzf' })
# )
# ```
#
# With older vimscript:
#
# ```VimL
# packadd vim-packix
#
# call packix#setup({ packix ->
#   packix.Add('halostatue/vim-packix', { 'type': 'opt' })
#   packix.Add('junegunn/fzf', { 'do': './install --all && ln -s $(pwd) ~/.fzf' })
# })
# ```
export def Setup(Callback: any, opts: Opts = {})
  if Callback->empty()
    throw 'Provide valid callback to packix setup via string or funcref.'
  endif

  if Callback->type() == v:t_func
    SetupCallback = Callback
  elseif Callback->type() == v:t_string
    if !exists('*' .. Callback)
      throw 'Function ' .. Callback ..
        ' does not exist for packix setup. Try providing a function or funcref.'
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
  Instance = Manager.new(opts)
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

export def Plugins(): list<PluginInfo>
  return EnsureInstance().GetPlugins()
enddef

export def PluginNames(): list<string>
  return EnsureInstance().GetPluginNames()
enddef

export def GetPlugin(name: string): PluginInfo
  return EnsureInstance().GetPlugin(name)
enddef

export def HasPlugin(name: string): bool
  return EnsureInstance().HasPlugin(name)
enddef

export def IsPluginInstalled(name: string): bool
  return EnsureInstance().IsPluginInstalled(name)
enddef

export def Version(): string
  return Manager.VERSION
enddef

def RunCommand(cmd: string, opts: any = null)
  EnsureInstance()

  if cmd ==? 'install'
    Install(opts == null ? {} : opts)
  elseif cmd ==? 'update'
    Update(opts == null ? {} : opts)
  elseif cmd ==? 'clean'
    Clean()
  elseif cmd ==? 'status'
    Status()
  endif
enddef

def RunMethod(method: string, direction: string = '')
  EnsureInstance()

  if method ==? 'quit'
    Instance.Quit()
  elseif method ==? 'open_sha'
    Instance.OpenSha()
  elseif method ==? 'open_stdout'
    Instance.OpenOutput()
  elseif method ==? 'goto_plugin'
    Instance.GotoPlugin(direction)
  elseif method ==? 'status'
    Instance.Status()
  elseif method ==? 'open_plugin_details'
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

def EnsureInstance(): Manager
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
