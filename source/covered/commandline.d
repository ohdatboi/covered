module covered.commandline;

import covered.loader;
import std.array : array;
import std.algorithm : each, map, filter, joiner, sort, sum;
import std.getopt : getopt, defaultGetoptPrinter, config;
import std.file : exists, isDir, getcwd, dirEntries, SpanMode;
import std.path : extension;
import std.parallelism : taskPool;
import std.range : tee, chain, enumerate;
import std.stdio;
import std.string : rightJustify;

enum MODE {
	SIMPLE,
	SOURCE,
	BLAME,
	AVERAGE,
}

int coveredMain(string[] args) {
	string[] m_files;
	string[] m_dirs;
	bool m_verbose;
	MODE m_mode;

	void parseMode(string option) {
		switch(option) {
		case "coverage|c":
			m_mode = MODE.SIMPLE;
			break;
		case "source|s":
			m_mode = MODE.SOURCE;
			break;
		case "blame|b":
			m_mode = MODE.BLAME;
			break;
		case "average|a":
			m_mode = MODE.AVERAGE;
			break;
		default: assert(0);
		}
	}

	auto hlp = getopt(
		args,
		config.passThrough,
		"coverage|c", "Reports code coverage (default)", &parseMode,
		"source|s", "Shows source code, number of executions of each line, and it's code coverage", &parseMode,
		"blame|b", "Shows list of files ordered by code coverage", &parseMode,
		"average|a", "Reports average code coverage across all passed files", &parseMode,
		"verbose|v", "Verbose output", &m_verbose
	);

	if(hlp.helpWanted) {
		defaultGetoptPrinter(
			"Usage:\tcovered <options> files dirs\n\n" ~
			"Covered processes output of code coverage analysis performed by the D programming language compiler (DMD/LDC/GDC)\n\n" ~
			"Every option below works with any number of files/directories specified in command line.\n" ~
			"If nothing is specified, it looks for '*.lst' files in current working directory\n\n" ~
			"Options:", hlp.options);
		return 0;
	}

	args = args[1..$]; // Delete 1st argument (program name)

	foreach(a; args) { // Process other arguments
		if(a.exists) {
			if(a.isDir) {
				m_dirs ~= a;
			} else {
				if(a.extension == ".lst") {
					m_files ~= a;
				} else {
					stderr.writefln("Warning: %s is not an '*.lst' file", a); // It is allowed to pass non-lst files, but this warning will be shown
					m_files ~= a;
				}
			}
		} else {
			stderr.writefln("Error: %s doesn't exist", a);
		}
	}

	if(!m_files.length && !m_dirs.length) // If nothing passed, try current working dir
		m_dirs ~= getcwd();

	final switch(m_mode) with(MODE) {
	case SIMPLE:
		m_files.openFilesAndDirs(m_dirs)
			.each!(a =>a.getCoverage() == float.infinity
				? writefln("%s has no code", a.getSourceFile)
				: writefln("%s is %.2f%% covered", a.getSourceFile, a.getCoverage));
		break;
	case SOURCE:
		m_files.openFilesAndDirs(m_dirs)
			.each!((a) {
				writeln("+-------------------");
				writefln("| File: %s", a.getFile);
				writefln("| Source file: %s", a.getSourceFile);
				if(a.getCoverage == float.infinity) {
					writefln("| Coverage: none (no code)", a.getSourceFile);
				} else {
					writefln("| Coverage: %.2f%%", a.getCoverage);
				}
				writeln("+-------------------");
				a.byEntry
					.each!(x => m_verbose
						? x.Used
							? "%5d|%s".writef(x.Count, x.Source)
							: "     |%s".writef(x.Source)
						: x.Source.write);
			});
		break;
	case BLAME:
		m_files.openFilesAndDirs(m_dirs)
			.filter!(a => a.getCoverage != float.infinity)
			.array
			.sort!((a, b) => a.getCoverage < b.getCoverage)
			.each!(a => m_verbose
				? "%-50s | %-50s | %.2f%%".writefln(
					a.getSourceFile.length > 50
						? a.getSourceFile[$-50..$]
						: a.getSourceFile.rightJustify(50),
					a.getFile.length > 50
						? a.getFile[$-50..$]
						: a.getFile.rightJustify(50),
					a.getCoverage)
				: "%-50s | %.2f%%".writefln(
					a.getSourceFile.length > 50
						? a.getSourceFile[$-50..$]
						: a.getSourceFile.rightJustify(50),
					a.getCoverage));
		break;
	case AVERAGE:
		size_t count;
		"Average: %.2f%%"
			.writefln(
				m_files.openFilesAndDirs(m_dirs)
				.filter!(a => a.getCoverage != float.infinity)
				.map!(a => a.getCoverage)
				.tee!(a => ++count)
				.sum / count);
		break;
	}
	return 0;
}
