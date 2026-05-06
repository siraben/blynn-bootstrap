#include <stdio.h>
#include <stdlib.h>
#include "M2libc/bootstrappable.h"

FILE* source_file;
FILE* destination_file;

int scrub_line_comment()
{
	int c = fgetc(source_file);
	while(10 != c)
	{
		require(EOF != c, "hit EOF in line comment\nThis is not valid input\n");
		c = fgetc(source_file);
	}
	return c;
}

int preserve_string()
{
	int c = fgetc(source_file);
	int escape = FALSE;
	do
	{
		if(!escape && '\\' == c ) escape = TRUE;
		else escape = FALSE;

		if(!escape) fputc(c, destination_file);
		c = fgetc(source_file);
		if(escape && 'n' == c)
		{
			fputc('\n', destination_file);
			c = fgetc(source_file);
		}
		require(EOF != c, "Unterminated string\n");
	} while(escape || (c != '"'));
	return fgetc(source_file);
}


void process_file()
{
	int c;

	do
	{
		c = fgetc(source_file);
		if('"' == c) preserve_string();
		else if('#' == c) c = scrub_line_comment();
	} while(EOF != c);
}

int main(int argc, char **argv)
{
	source_file = stdin;
	destination_file = stdout;

	int option_index = 1;
	while(option_index <= argc)
	{
		if(NULL == argv[option_index])
		{
			option_index = option_index + 1;
		}
		else if(match(argv[option_index], "-o") || match(argv[option_index], "--output"))
		{
			destination_file = fopen(argv[option_index + 1], "w");

			if(NULL == destination_file)
			{
				fputs("The file: ", stderr);
				fputs(argv[option_index + 1], stderr);
				fputs(" can not be opened!\n", stderr);
				exit(EXIT_FAILURE);
			}
			option_index = option_index + 2;
		}
		else if(match(argv[option_index], "-f") || match(argv[option_index], "--file"))
		{
			source_file = fopen(argv[option_index + 1], "r");
			if(NULL == source_file)
			{
				fputs("The file: ", stderr);
				fputs(argv[option_index + 1], stderr);
				fputs(" can not be opened!\n", stderr);
				exit(EXIT_FAILURE);
			}
			option_index = option_index + 2;
		}
		else
		{
			fputs("bad command: ", stdout);
			fputs(argv[option_index], stdout);
			fputs("\n", stdout);
			exit(EXIT_FAILURE);
		}
	}

	process_file();
	exit(EXIT_SUCCESS);
}
