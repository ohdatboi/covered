module covered.loader;

import std.array : array;
import std.algorithm : map, each, filter, canFind, until, find, stripLeft;
import std.conv : to;
import std.range : drop, tee, isInputRange, ElementType;
import std.regex : matchFirst, regex;
import std.stdio : File;
import std.typecons : Tuple, tuple;
version(unittest) import fluent.asserts;

auto openFilesDirs(string[] files, string[] dirs) {
	import std.algorithm : joiner;
	import std.file : exists, dirEntries, SpanMode;
	import std.range : chain;
	return files
		.chain(dirs
			.map!(a => a.dirEntries("[!.]*.lst", SpanMode.shallow))
			.joiner)
		.filter!(a => a.exists)
		.map!(a => CoverageLoader(a));
}

struct CoverageLoader {
	private {
		File m_file;
		char[] m_buffer;

		string m_sourcefile;

		bool m_coverage_computed = false;
		float m_coverage;

		bool m_stats_available = 0;

		size_t m_covered;
		size_t m_total;
	}

	this(string fname) { this(File(fname, "r")); }

	this(File f) { m_file = f; }

	ByEntryRange byEntry() { return ByEntryRange(m_file); }

	private void getCoveredAndTotalLines() {
		import std.string : indexOf, stripLeft;

		m_file.seek(0);
		m_buffer.reserve(4096);

		m_covered = m_total = 0;

		while(m_file.readln(m_buffer)) {
			immutable bar = m_buffer.indexOf('|');

			if(bar == -1) {
				break;
			} else {
				auto num = m_buffer[0..bar].stripLeft;
				if(num.length) {
					foreach(ref c; num) {
						if(c != '0') {
							++m_covered;
							break;
						}
					}
					++m_total;
				}
			}
		}

		m_stats_available = true;
	}

	size_t getTotalCount() {
		if(!m_stats_available)
			this.getCoveredAndTotalLines();

		return m_total;
	}

	size_t getCoveredCount() {
		if(!m_stats_available)
			this.getCoveredAndTotalLines();

		return m_covered;
	}

	float getCoverage() {
		if(!m_stats_available)
			this.getCoveredAndTotalLines();

		if(!m_coverage_computed) {
			if(m_covered == 0 && m_total == 0) {
				m_coverage = float.infinity;
			} else {
				m_coverage = m_covered.to!float / m_total.to!float * 100.0f;
			}
		}

		return m_coverage;
	}

	string getSourceFile() {
		if(!m_sourcefile.length) {
			import std.algorithm : canFind;

			m_file.seek(0);
			m_buffer.reserve(4096);

			while(m_file.readln(m_buffer)) {
				if(m_buffer.canFind('|'))
					continue;

				auto m = m_buffer.matchFirst(
					regex(r"(.+\.d) (?:(?:is \d+% covered)|(?:has no code))"));

				if(m.empty)
					continue;

				m_sourcefile = m[1].dup;
				break;
			}
		}

		return m_sourcefile;
	}

	string getName() { return m_file.name; }
}

@("getCoveredCount(), getTotalCount() and getCoverage() produce expected results")
unittest {
	auto c = CoverageLoader2("sample/hello.lst");
	c.getCoveredCount.should.be.equal(1);
	c.getTotalCount.should.be.equal(1);

	c.getCoverage.should.be.equal(100.0f);
}

@("getSourceFile() returns correct file name")
unittest {
	CoverageLoader2("sample/hello.lst").getSourceFile.should.be.equal("hello.d");
}

struct Entry {
	bool Used;
	size_t Count;
	string Source;
}

struct ByEntryRange {
	private {
		File m_file;
		Entry m_last;
		bool m_empty;
		char[] m_buffer;
	}

	this(File f) {
		m_buffer.reserve(4096);
		m_file = f;
		this.popFront;
	}

	@property Entry front() { return m_last; }
	@property bool empty() { return m_empty; }

	void popFront() {
		import std.string : indexOf, stripLeft;
		import std.conv : to;
		immutable read = m_file.readln(m_buffer);
		if(read == 0) {
			m_empty = true;
			return;
		} else {
			immutable bar = m_buffer[0..read].indexOf('|');

			if(bar == -1) {
				m_empty = true;
				return;
			} else {
				auto num = m_buffer[0..bar].stripLeft;
				if(num.length) {
					m_last.Used = true;
					m_last.Count = num.to!size_t;
				} else {
					m_last.Used = false;
					m_last.Count = 0;
				}

				m_last.Source = m_buffer[bar + 1 .. read].dup;
			}
		}
	}
}

@("ByElementRange produces expected results")
unittest {
	import std.array : array;

	ByEntryRange(File("sample/hello.lst" ,"r")).array
		.should.be.equal([
			Entry(false, 0, "import std.stdio;\n"),
			Entry(false, 0, "\n"),
			Entry(false, 0, "void main() {\n"),
			Entry(true, 1, "        writeln(\"Hello world!\");\n"),
			Entry(false, 0, "}\n"),
		]);
}
