## Copyright (c) 2013 Miguel Bazdresch
##
## This file is distributed under the 2-clause BSD License.

function gnuplot_init()
    global gnuplot_state

    pr = (0,0,0,0) # stdin, stdout, stderr, pid
    try
		pr = popen3(`gnuplot`)
    catch
        error("There was a problem starting up gnuplot.")
    end
    # It's possible that `popen3` runs successfully, but gnuplot exits
    # immediately. Double-check that gnuplot is running at this point.
    if Base.process_running(pr[4])
	    gnuplot_state.running = true
	    gnuplot_state.fid = pr
		# Start tasks to read and write gnuplot's pipes
		yield()  # get async tasks started (code blocks without this line)
		notify(StartPipes)
	else
        error("There was a problem starting up gnuplot.")
	end
end

# Async tasks to read/write to gnuplot's pipes.
const StartPipes = Condition()  # signal to start reading pipes

# This task reads all characters available from gnuplot's stdout.
@async while true
	wait(StartPipes)
	pout = gnuplot_state.fid[2]
	while true
		if !isopen(pout)
			break
		end
		gnuplot_state.gp_stdout = ascii(readavailable(pout))
	end
end

# This task reads all characters available from gnuplot's stderr.
@async while true
	wait(StartPipes)
	perr = gnuplot_state.fid[3]
	while true
		if !isopen(perr)
			break
		end
		gnuplot_state.gp_stderr = ascii(readavailable(perr))
	end
end

# close gnuplot pipe
function gnuplot_exit(x...)
    global gnuplot_state

    if gnuplot_state.running
        # close pipe
        close(gnuplot_state.fid[1])
        close(gnuplot_state.fid[2])
        close(gnuplot_state.fid[3])
    end
    # reset gnuplot_state
    gnuplot_state.running = false
    gnuplot_state.current = 0
    gnuplot_state.figs = Any[]
    return 0
end

# Return index to figure with handle 'c'. If no such figure exists, returns 0.
function findfigure(c)
    global gnuplot_state
    i = 0
    for j = 1:length(gnuplot_state.figs)
        if gnuplot_state.figs[j].handle == c
            i = j
            break
        end
    end
    return i
end

# convert marker string description to gnuplot's expected number
function pointtype(x::AbstractString)
    if x == "+"
        return 1
    elseif x == "x"
        return 2
    elseif x == "*"
        return 3
    elseif x == "esquare"
        return 4
    elseif x == "fsquare"
        return 5
    elseif x == "ecircle"
        return 6
    elseif x == "fcircle"
        return 7
    elseif x == "etrianup"
        return 8
    elseif x == "ftrianup"
        return 9
    elseif x == "etriandn"
        return 10
    elseif x == "ftriandn"
        return 11
    elseif x == "edmd"
        return 12
    elseif x == "fdmd"
        return 13
    end
    return 1
end

# return configuration string for a single plot
function linestr_single(conf::CurveConf)
    s = ""
    if conf.legend != ""
        s = string(s, " title '", conf.legend, "' ")
    else
        s = string(s, "notitle ")
    end
    s = string(s, " with ", conf.plotstyle, " ")
    if conf.color != ""
        s = string(s, "linecolor rgb '", conf.color, "' ")
    end
    s = string(s, "lw ", string(conf.linewidth), " ")
    # some plotstyles don't allow point specifiers
    cp = conf.plotstyle
    if cp != "lines" && cp != "impulses" && cp != "pm3d" && cp != "image" &&
        cp != "rgbimage" && cp != "boxes" && cp != "dots" && cp != "steps" &&
        cp != "fsteps" && cp != "fillsteps" && cp != "financebars"
        if conf.marker != ""
            s = string(s, "pt ", string(pointtype(conf.marker)), " ")
        end
        s = string(s, "ps ", string(conf.pointsize), " ")
    end
    return s
end

# build a string with plot commands according to configuration
function linestr(curves::Vector{CurveData}, cmd::AbstractString, file::AbstractString)
    # We have to insert "," between plot commands. One easy way to do this
    # is create the first plot command, then the rest
    # We also need to keep track of the current index (starts at zero)
    index = 0
    s = string(cmd, " '", file, "' ", " i 0 ", linestr_single(curves[1].conf))
    if length(curves) > 1
        for i in curves[2:end]
            index += 1
            s = string(s, ", '", file, "' ", " i ", string(index)," ",
                linestr_single(i.conf))
        end
    end
    return s
end

# create a Z-coordinate matrix from x, y coordinates and a function
function meshgrid(x,y,f)
    Z = zeros(length(x),length(y))
    for k = 1:length(x)
        Z[k,:] = [ f(i,j) for i=x[k], j=y ]
    end
    return Z
end

# dereference CurveConf, by adding a method to copy()
function copy(conf::CurveConf)
    new = CurveConf()
    new.legend = conf.legend
    new.plotstyle = conf.plotstyle
    new.color = conf.color
    new.marker = conf.marker
    new.linewidth = conf.linewidth
    new.pointsize = conf.pointsize
    return new
end

# dereference AxesConf
function copy(conf::AxesConf)
    new = AxesConf()
    new.title = conf.title
    new.xlabel = conf.xlabel
    new.ylabel = conf.ylabel
    new.zlabel = conf.zlabel
    new.fill = conf.fill
    new.grid = conf.grid
    new.box = conf.box
    new.axis = conf.axis
    new.xrange = conf.xrange
    new.yrange = conf.yrange
    new.zrange = conf.zrange
    return new
end

# Build a "set term" string appropriate for the terminal type
function termstring(term::AbstractString)
    global gnuplot_state
    global gaston_config

    gc = gaston_config

    if is_term_screen(term)
        ts = "set term $term $(gnuplot_state.current)"
    else
        if term == "pdf"
            s = "set term pdfcairo $(gc.print_color) "
            s = "$s font \"$(gc.print_fontface),$(gc.print_fontsize)\" "
            s = "$s fontscale $(gc.print_fontscale) "
            s = "$s linewidth $(gc.print_linewidth) "
            s = "$s size $(gc.print_size)"
        elseif term == "eps"
            s = "set term epscairo $(gc.print_color) "
            s = "$s font \"$(gc.print_fontface),$(gc.print_fontsize)\" "
            s = "$s fontscale $(gc.print_fontscale) "
            s = "$s linewidth $(gc.print_linewidth) "
            s = "$s size $(gc.print_size)"
        elseif term == "png"
            s = "set term pngcairo $(gc.print_color) "
            s = "$s font \"$(gc.print_fontface),$(gc.print_fontsize)\" "
            s = "$s fontscale $(gc.print_fontscale) "
            s = "$s linewidth $(gc.print_linewidth) "
            s = "$s size $(gc.print_size)"
        elseif term == "gif"
            s = "set term gif "
            s = "$s font $(gc.print_fontface) $(gc.print_fontsize) "
            s = "$s fontscale $(gc.print_fontscale) "
            s = "$s linewidth $(gc.print_linewidth) "
            s = "$s size $(gc.print_size)"
        elseif term == "svg"
            s = "set term svg "
            s = "$s font \"$(gc.print_fontface),$(gc.print_fontsize)\" "
            s = "$s linewidth $(gc.print_linewidth) "
            s = "$s size $(gc.print_size)"
        end
        ts = "$s \nset output \"$(gc.outputfile)\""
    end
    return ts
end

# send gnuplot the current figure's configuration
function gnuplot_send_fig_config(config)
	# fill style
	if config.fill != ""
		gnuplot_send(string("set style fill ",config.fill))
	end
	# grid
	if config.grid != ""
		if config.grid == "on"
			gnuplot_send(string("set grid"))
		else
			gnuplot_send(string("unset grid"))
		end
	end
    # legend box
    if config.box != ""
        gnuplot_send(string("set key ",config.box))
    end
    # plot title
    if config.title != ""
        gnuplot_send(string("set title '",config.title,"' "))
    end
    # xlabel
    if config.xlabel != ""
        gnuplot_send(string("set xlabel '",config.xlabel,"' "))
    end
    # ylabel
    if config.ylabel != ""
        gnuplot_send(string("set ylabel '",config.ylabel,"' "))
    end
    # zlabel
    if config.zlabel != ""
        gnuplot_send(string("set zlabel '",config.zlabel,"' "))
    end
    # axis log scale
    if config.axis != "" || config.axis != "normal"
        if config.axis == "semilogx"
            gnuplot_send("set logscale x")
        end
        if config.axis == "semilogy"
            gnuplot_send("set logscale y")
        end
        if config.axis == "loglog"
            gnuplot_send("set logscale xy")
        end
    end
    # ranges
    gnuplot_send("set autoscale")
    if config.xrange != ""
        gnuplot_send(string("set xrange ",config.xrange))
    end
    if config.yrange != ""
        gnuplot_send(string("set yrange ",config.yrange))
    end
    if config.zrange != ""
        gnuplot_send(string("set zrange ",config.zrange))
    end
end

# Validation functions.
# These functions validate that configuration parameters are valid and
# supported. They return true iff the argument validates.

# Validate terminal type.
function validate_terminal(s::AbstractString)
    supp_terms = ["qt", "wxt", "x11", "svg", "gif", "png", "pdf", "aqua", "eps"]
    if s == "aqua" && OS_NAME != :Darwin
        return false
    end
    if in(s, supp_terms)
        return true
    end
    return false
end

# Identify terminal by type: file or screen
function is_term_screen(s::AbstractString)
    screenterms = ["qt", "wxt", "x11", "aqua"]
    if in(s, screenterms)
        return true
    end
    return false
end

function is_term_file(s::AbstractString)
    screenterms = ["svg", "gif", "png", "pdf", "eps"]
    if in(s, screenterms)
        return true
    end
    return false
end

# Valid plotstyles supported by gnuplot's plot
function validate_2d_plotstyle(s::AbstractString)
    valid = ["lines", "linespoints", "points", "impulses", "boxes",
        "errorlines", "errorbars", "dots", "steps", "fsteps", "fillsteps",
        "financebars"]
    if in(s, valid)
        return true
    end
    return false
end

# Valid plotstyles supported by gnuplot's splot
function validate_3d_plotstyle(s::AbstractString)
    valid = ["lines", "linespoints", "points", "impulses", "pm3d",
            "image", "rgbimage", "dots"]
    if in(s, valid)
        return true
    end
    return false
end

# Valid axis types
function validate_axis(s::AbstractString)
    valid = ["", "normal", "semilogx", "semilogy", "loglog"]
    if in(s, valid)
        return true
    end
    return false
end

# Valid markers supported by Gaston
function validate_marker(s::AbstractString)
    valid = ["", "+", "x", "*", "esquare", "fsquare", "ecircle", "fcircle",
    "etrianup", "ftrianup", "etriandn", "ftriandn", "edmd", "fdmd"]
    if in(s, valid)
        return true
    end
    return false
end

# Validate fill style
function validate_fillstyle(s::AbstractString)
	valid = ["","empty","solid","pattern"]
	if in(s,valid)
		return true
	end
	return false
end

# Validate grid styles
function validate_grid(s::AbstractString)
	valid = ["", "on", "off"]
	if in(s,valid)
		return true
	end
	return false
end

function validate_range(s::AbstractString)

    # floating point, starting with a dot
    f1 = "[-+]?\\.\\d+([eE][-+]?\\d+)?"
    # floating point, starting with a digit
    f2 = "[-+]?\\d+(\\.\\d*)?([eE][-+]?\\d+)?"
    # floating point
    f = "($f1|$f2)"
    # autoscale directive (i.e. `*` surrounded by
    # optional bounds lb < * < ub)
    as = "(($f\\s*<\\s*)?\\*(\\s*<\\s*$f)?)"
    # full range item: a floating point, or an
    # autoscale directive, or nothing
    it = "(\\s*($as|$f)?\\s*)"

    # empty range
    er = "\\[\\s*\\]"
    # full range: two colon-separated items
    fr = "\\[$it:$it\\]"

    # range regex
    rx = Regex("^\\s*($er|$fr)\\s*\$")

    if isempty(s) || ismatch(rx, s)
        return true
    end
    return false
end

function writemime(io::IO, ::MIME"image/png", x::Figure)
	# The plot is written to /tmp/gaston-ijula.png. Read the file and
	# write it to io.
	data = open(readbytes, "$(gnuplot_state.tmpdir)gaston-ijulia.png","r")
	write(io,data)
end

# Execute command `cmd`, and return a tuple `(in, out, err, r)`, where
# `in`, `out`, `err` are pipes to the process' STDIN, STDOUT, and STDERR, and
# `r` is a process descriptor.
function popen3(cmd::Cmd)
    pin = Base.Pipe()
    out = Base.Pipe()
    err = Base.Pipe()
    r = spawn(cmd, (pin, out, err))
    Base.close_pipe_sync(out.in)
    Base.close_pipe_sync(err.in)
    Base.close_pipe_sync(pin.out)
    Base.start_reading(out.out)
    Base.start_reading(err.out)
    return (pin.in, out.out, err.out, r)
end
