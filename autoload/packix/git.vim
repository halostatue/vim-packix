vim9script

import autoload 'packix/core.vim'

type Opts = dict<any>

var parts = core.System('git --version')
  ->get(0, '')
  ->split('\D\+')
  ->map((_, part: string): number => part->str2nr())

export const Version = {
  major: parts->get(0, 0),
  minor: parts->get(1, 0),
  patch: parts->get(2, 0)
}

def GitCommand(args: any, dir: string = null_string): string
  var cmd = args->type() ==# v:t_list
    ? args->map((_, v) => v->shellescape())->join(' ')
    : args

  return dir ==? null_string ? $'git {cmd}' : $'git -C {dir->shellescape()} {cmd}'
enddef

def ParseRev(output: list<string>): string
  var rev = output->get(0, '')
  return rev =~? '^fatal' ? '' : rev
enddef

export def CurrentRevision(opts: Opts = {}): string
  return ParseRev(core.System(GitCommand('rev-parse HEAD', opts->get('dir', null_string))))
enddef

export def CurrentRevisionAsync(Lambda: func, opts: Opts = {})
  core.SystemAsync(GitCommand('rev-parse HEAD', opts->get('dir', null_string)),
    (output) => {
      Lambda(ParseRev(output))
    }
  )
enddef

export def HeadRef(opts: Opts = {}): string
  return ParseRev(core.System(GitCommand('rev-parse --abbrev-ref HEAD', opts->get('dir', null_string))))
enddef

export def HeadRefAsync(Lambda: func, opts: Opts = {})
  core.SystemAsync(GitCommand('rev-parse --abbrev-ref HEAD', opts->get('dir', null_string)),
    (output) => {
      Lambda(ParseRev(output))
    }
  )
enddef

def ParseSymbolicRef(output: list<string>, remote: string): string
  var ref = output->get(0, '')
  return ref =~? '^fatal' ? '' : ref->substitute($'^{remote}/', '', '')
enddef

export def MainBranch(opts: Opts): string
  var remote = opts->get('remote', 'origin')

  return ParseSymbolicRef(
    core.System(
      GitCommand(['symbolic-ref', $'refs/remotes/{remote}/HEAD', '--short'], opts->get('dir', null_string))
    ),
    remote
  )
enddef

export def MainBranchAsync(Lambda: func, opts: Opts = {})
  var remote = opts->get('remote', 'origin')

  core.SystemAsync(
    GitCommand(['symbolic-ref', $'refs/remotes/{remote}/HEAD', '--short'], opts->get('dir', null_string)),
    (output) => {
      Lambda(ParseSymbolicRef(output, remote))
    }
  )
enddef

export def LatestCommits(opts: Opts = {}): list<string>
  var commits = core.System(
    GitCommand(
      [
        'log', '--color=never', '--pretty=format:%h %s (%cr)', '--no-show-signature',
        'HEAD@{1}..'
      ],
      opts->get('dir', null_string)
    )
  )

  return commits->filter((_, v) => v !=? '' && v !~? '^fatal')
enddef

export def Show(sha: string, opts: Opts = {}): list<string>
  return core.System(
    GitCommand(['show', '--no-color', '--pretty=medium', sha], opts->get('dir', null_string))
  )
enddef

export def CheckoutCommand(target: string, opts: Opts = {}): string
  return target->empty() ? '' : GitCommand(['checkout', target], opts->get('dir', null_string))
enddef

export def RefreshCurrentBranchCommand(opts: Opts = {}): string
  return GitCommand('pull --ff-only --progress --rebase=false', opts->get('dir', null_string))
enddef

export def FetchURLCommand(url: string, opts: Opts = {}): string
  return GitCommand(['fetch', url, '--depth', '999999'])
enddef

export def CloneCommand(url: string, opts: Opts = {}): string
  var dir = opts->get('dir', null_string)

  if dir->empty()
    throw 'git.Clone must be provided a `dir` value.'
  endif

  var args = [
    'clone', '--progress', '--depth', opts->get('depth', 5),
    '--no-single-branch', url, dir
  ]

  if opts->get('commit')->empty()
    if !opts->get('tag')->empty()
      args += ['--branch', opts->get('tag')]
    elseif !opts->get('branch')->empty()
      args += ['--branch', opts->get('branch')]
    endif
  endif

  return GitCommand(args)
enddef

export def UpdateSubmoduleCommand(opts: Opts = {}): string
  var args = ['submodule', 'update', '--init', '--recursive']

  if Version.major >= 2 && Version.minor >= 11
    args->add('--progress')
  endif

  return GitCommand(args, opts->get('dir', null_string))
enddef

export def CdCommand(dir: string): string
  return $'cd{core.IS_WINDOWS ? ' /d' : ''} {dir->shellescape()}'
enddef

