vim9script

type Opts = dict<any>

export class Info
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

export class Manager
  var _jobs: dict<Info>
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

    this._jobs[jobId] = Info.new(job, opts)

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
      var info: Info = this._jobs[jobId]

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
      var info: Info = this._jobs[jobId]
      var close_stdin = opts->get('close_stdin', 0) > 0

      # There is no easy way to know when ch_sendraw() finishes writing data
      # on a non-blocking channels -- has('patch-8.1.889') -- and because of
      # this, we cannot safely call ch_close_in().  So when we find ourselves
      # in this situation (i.e. noblock=1 and close stdin after send) we fall
      # back to using _FlushVimSendraw() and wait for transmit buffer to be
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

  def _ExitCallback(jobId: number, opts: Opts, job: any, jobStatus: number)
    if opts->has_key('on_exit')
      opts.on_exit(jobId, jobStatus, 'exit')
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
