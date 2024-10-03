vim9script noclear

const PROGRESS_ICONS = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
export const ICONS = { ok: '✓', error: '✗', waiting: '+', progress: join(PROGRESS_ICONS, '') }
export const ICONS_STR = ICONS->values()->join('')

var _counter: number = 0

def Next(): string
  var icon = PROGRESS_ICONS[_counter]

  _counter += 1

  if _counter >= len(PROGRESS_ICONS)
    _counter = 0
  endif

  return icon
enddef

export def SetOk(name: string, text: string): string
  return Set('ok', name, text)
enddef

export def SetProgress(name: string, text: string): string
  return Set('progress', name, text)
enddef

export def SetError(name: string, text: string): string
  return Set('error', name, text)
enddef

export def Set(type: string, name: string, text: string): string
  return printf(
    '%s %s — %s',
    type ==? 'progress' ? Next() : ICONS[type],
    name,
    text
  )
enddef
