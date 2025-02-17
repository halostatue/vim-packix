vim9script

type Opts = dict<any>

import autoload 'packix/core.vim'
import autoload 'packix/git.vim'
import autoload 'packix/status.vim'

export class Info
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

export class Plugin
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

  var state: string = ''
  var stateMessage: string = ''
  var headRef: string = ''
  var mainBranch: string = ''

  var do: any
  var triggers: dict<list<any>> = { map: [], cmd: [] }
  var requires: any

  var _AddRequired: func(string, any)

  var _eventMessages: list<string> = []
  var _hookEventMessages: list<string> = []

  def new(plugin: dict<any>)
    var name = plugin->get('url')
    var opts: Opts = plugin->get('opts', {})

    this._AddRequired = plugin->get('add_required')
    this.type = opts->get('type', plugin->get('default_type', 'start'))
    this.branch = opts->get('branch', '')
    this.commit = opts->get('commit', '')
    this.tag = opts->get('tag', '')
    this.frozen = opts->get('frozen', false)
    this.do = opts->get('do', '')
    this.local = opts->get('local', false)
    this.requires = core.Wrap(opts->get('requires', []))

    if ['opt', 'start']->index(this.type) < 0
      this.type = 'start'
    endif

    this.name = opts->get('name')->empty() ? name->split('/')[-1] : opts.name
    this.dir = [plugin->get('dir'), this.type, this.name]->join(core.SLASH)

    this.rtp = opts->get('rtp', '')

    if !this.rtp->empty()
      var rtp = this.rtp
        ->substitute('[\\\/]$', '', '')
        ->substitute('[\\\/]', '__', 'g')

      this.rtpDir = $'{this.dir}__${rtp}'
    endif

    # Deferred loading adapted from junegunn/vim-plug, only supporting commands, not Plug
    # maps, for now. Applied *only* for 'opt' plugins.
    if this.type == 'opt' && opts->has_key('on')
      for trigger in core.Wrap(opts.on)
        if trigger !~# '^:\=[A-Z]'
          throw $'Invalid `on` option: {trigger} should start with an uppercase letter.'
        endif

        var t = trigger->substitute('^:', '', '')->substitute('!*$', '', '')

        core.DeferCommand(t, this)
        this.triggers.cmd->add(t)
      endfor
    endif

    this.url = this.local ? name : core.NameToUrl(name)

    if this.dir->isdirectory()
      this.installed = true

      if core.IS_WINDOWS
        this._UpdateRevisionAsync()
        this._UpdateHeadRefAsync()
        this._UpdateMainBranchAsync()
      endif
    endif

    for require in this.requires
      this._AddRequired(this.name, require)
    endfor
  enddef

  def RemoveTriggers()
    for cmd in this.triggers.cmd
      execute $'silent! delcommand {cmd}'
    endfor
  enddef

  def SetUpdateFailed()
    this.updateFailed = true
  enddef

  def SetHookFailed()
    this.hookFailed = true
  enddef

  def GetInfo(): Info
    if !core.IS_WINDOWS
      this._UpdateRevision()
      this._UpdateHeadRef()
      this._UpdateMainBranch()
    endif

    return Info.new(
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
    if !core.IS_WINDOWS
      this._UpdateRevision()
    endif

    this.SetState('progress', this.installed ? 'Updating…' : 'Installing…')
  enddef

  def SetState(state: string, message: string)
    this.state = state
    this.stateMessage = message
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
      return core.INSTALLED
    endif

    if this._HasUpdates()
      this.updated = true
      this._GetLastUpdate()
      this._SymlinkRtp()
      return core.UPDATED
    endif

    return this.local ? core.LOCAL_UP_TO_DATE : core.UP_TO_DATE
  enddef

  def GetLastHookEventMessage(): string
    return this._hookEventMessages->get(-1, '')
  enddef

  def GetLastEventMessage(): string
    return this._eventMessages->get(-1, '')
  enddef

  def LogHookEventMessages(messages: list<string>)
    for message in messages
      var trimmed = core.Trim(message)

      if !trimmed->empty() && this._hookEventMessages->index(trimmed) < 0
        this._hookEventMessages->add(trimmed)
      endif
    endfor
  enddef

  def LogEventMessages(messages: list<string>)
    for message in messages
      var trimmed = core.Trim(message)

      if !trimmed->empty() && this._eventMessages->index(trimmed) < 0
        this._eventMessages->add(trimmed)
      endif
    endfor
  enddef

  def GetShortHookErrorMessage(): string
    return core.Trim(this._hookEventMessages->get(-1, ''))
  enddef

  def GetShortErrorMessage(): string
    return core.Trim(this._eventMessages->get(-1, ''))
  enddef

  def GetStdoutMessages(): list<string>
    var result: list<string> = []

    var messages = this.hookFailed ? this._hookEventMessages : this._eventMessages

    for message in messages
      for line in message->split('\r')
        if !core.Trim(line)->empty()
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
      var statusText = $'Not installed.{last}'
      var result = [status.SetError(this.name, statusText)]

      if !error->empty()
        result->add($'  * {error}')
      endif

      return result
    endif

    if this.updateFailed
      return [
        status.SetError(this.name, 'Install/update failed. Last line of error message:'),
        $'  * {this.GetShortErrorMessage()}'
      ]
    endif

    if this.hookFailed
      return [
        status.SetError(this.name, 'Post hook failed. Last line of error message:'),
        $'  * {this.GetShortHookErrorMessage()}'
      ]
    endif

    if this.installedNow
      return [status.SetOk(this.name, 'Installed!')]
    endif

    if !this.updated
      this._GetLastUpdate()
    endif

    if this.lastUpdate->empty()
      return [status.SetOk(this.name, 'OK.')]
    endif

    var text = this.updated ? 'Updated!' : 'Last update:'
    var result = [status.SetOk(this.name, text)]

    for line in this.lastUpdate
      result->add($'  * {line}')
    endfor

    return result
  enddef

  def _UpdateRevision()
    this.rev = git.CurrentRevision({ dir: this.dir })
  enddef

  def _UpdateRevisionAsync()
    git.CurrentRevisionAsync(
      (rev) => {
        this.rev = rev
      },
      { dir: this.dir }
    )
  enddef

  def _UpdateHeadRef(): string
    if this.headRef->empty()
      this.headRef = git.HeadRef({ dir: this.dir })
    endif

    return this.headRef
  enddef

  def _UpdateHeadRefAsync()
    if this.headRef->empty()
      git.HeadRefAsync(
        (headRef) => {
          this.headRef = headRef
        },
        { dir: this.dir }
      )
    endif
  enddef

  def _UpdateMainBranch(): string
    if this.mainBranch->empty()
      this.mainBranch = git.MainBranch({ dir: this.dir })
    endif

    return this.mainBranch
  enddef

  def _UpdateMainBranchAsync()
    if this.mainBranch->empty()
      git.MainBranchAsync(
        (branch) => {
          this.mainBranch = branch
        },
        { dir: this.dir }
      )
    endif
  enddef

  def _GitCheckoutTarget(): string
    for target in [this.commit, this.tag, this.branch]
      if !target->empty()
        return target
      endif
    endfor

    return null_string
  enddef

  def _UpdateGitCommand(): string
    this._UpdateHeadRef()
    this._UpdateMainBranch()

    var target = this._GitCheckoutTarget()
    var checkoutCommand: string
    var isOnBranch = false

    if !target->empty() # a checkout target exists
      isOnBranch = target ==# this.branch
      checkoutCommand = git.CheckoutCommand(target)
    elseif this.headRef ==# 'HEAD' && !this.mainBranch->empty()
      isOnBranch = true
      checkoutCommand = git.CheckoutCommand(this.mainBranch)
    else
      isOnBranch = this.headRef ==# this.mainBranch
    endif

    var refreshCommand = isOnBranch
      ? git.RefreshCurrentBranchCommand()
      : git.FetchURLCommand(this.url)

    return [
      # cd [/d] <dir>
      git.CdCommand(this.dir),
      # git checkout <commit> | <tag> | <branch> | <main_branch>
      checkoutCommand,
      # git pull --ff-only --progress --rebase=false # on branch
      # git fetch <url> --depth 999999 # off branch
      refreshCommand,
      # git submodule update --init --recursive [--progress]
      git.UpdateSubmoduleCommand()
    ]->filter((_, v) => !v->empty())->join(' && ')
  enddef

  def _InstallGitCommand(depth: any): string
    var parts = [
      # git clone --progress <url> <dir> --depth <depth> --no-single-branch [--branch <target>]
      git.CloneCommand(this.url, { branch: this.branch, commit: this.commit, depth:
        depth->string(), dir: this.dir, tag: this.tag }),
      # cd [/d] <dir>
      git.CdCommand(this.dir),
      # git submodule update --init --recursive [--progress]
      git.UpdateSubmoduleCommand()
    ]

    if !this.commit->empty()
      # git checkout <commit>
      parts->add(git.CheckoutCommand(this.commit))
    endif

    return join(parts, ' && ')
  enddef

  def _LocalCommand(): string
    if this.dir->isdirectory()
      return null_string
    endif

    var cmd = core.SymlinkCommand(this.url->fnamemodify(':p'), this.dir)

    if !cmd->empty()
      return cmd
    endif

    return printf(
      'echo Cannot install %s locally, linking tool not found.', this.name
    )
  enddef

  def _HasUpdates(): bool
    return !this.rev->empty() && this.rev !=? git.CurrentRevision({ dir: this.dir })
  enddef

  def _GetLastUpdate()
    this.lastUpdate = git.LatestCommits({ dir: this.dir })
  enddef

  def _SymlinkRtp()
    if this.rtpDir->empty()
      return
    endif

    var dir = printf('%s/%s', this.dir, this.rtp)

    if !this.rtpDir->isdirectory()
      var cmd = core.SymlinkCommand(dir, this.rtpDir)

      if !cmd->empty()
        core.System(cmd)
      endif
    endif
  enddef
endclass

export def Load(wanted: Plugin)
  if &runtimepath->empty()
    &runtimepath = wanted.dir
  else
    &runtimepath ..= $',{wanted.dir}'
  endif

  for path in ['plugin/**/*.vim', 'after/plugin/**/*.vim']
    var full_path = printf('%s/%s', wanted.dir, path)

    if !full_path->glob()->empty()
      silent execute $'source {full_path}'
    endif
  endfor
enddef
