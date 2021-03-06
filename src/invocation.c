#include "invocation.h"

#include <errno.h>
#include <getopt.h>
#include <sodium.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#include "exit.h"
#include "help.h"
#include "memory.h"

invocation_state_t *parse_arguments_and_get_passphrase(int argc, char **argv) {
	if (argc < 2) {
		print_usage(argv[0]);
		exit(EXIT_BAD_INVOCATION);
	}

	invocation_state_t *result =
	    malloc_or_exit(sizeof(invocation_state_t), "invocation state");
	result->device = NULL;
	result->file = NULL;
	result->passphrase = NULL;
	result->obfuscate_device_info = false;
	result->kdf_hardness = kdf_hardness_unspecified;
	result->mixin = NULL;

	if (strcmp(argv[1], "help") == 0) {
		result->subcommand = subcommand_help;
	} else if (strcmp(argv[1], "version") == 0) {
		result->subcommand = subcommand_version;
	} else if (strcmp(argv[1], "enrol") == 0) {
		result->subcommand = subcommand_enrol;
	} else if (strcmp(argv[1], "generate") == 0) {
		result->subcommand = subcommand_generate;
	} else if (strcmp(argv[1], "enumerate") == 0) {
		result->subcommand = subcommand_enumerate;
	} else {
		print_usage(argv[0]);
		exit(EXIT_BAD_INVOCATION);
	}

	int c;
	bool invalid_invocation = false;
	while (1) {
		static struct option long_options[] = {
		    {"device", required_argument, 0, 'd'},
		    {"file", required_argument, 0, 'f'},
		    {"passphrase", required_argument, 0, 'p'},
		    {"mixin", required_argument, 0, 'm'},
		    {"kdf-hardness", required_argument, 0, 'k'},
		    {"obfuscate-device", no_argument, 0, 'o'},
		    {"help", no_argument, 0, 'h'},
		    {NULL, 0, NULL, 0},
		};

		/* getopt_long stores the option index here. */
		int option_index = 0;

		c = getopt_long(argc, argv, "d:f:p:m:k:oh", long_options,
		                &option_index);

		if (c == -1) {
			break;
		}

		switch (LOWERCASE(c)) {
		case 'd':
			result->device =
			    strdup_or_exit(optarg, "device path in invocation state");
			break;

		case 'f':
			result->file =
			    strdup_or_exit(optarg, "file path in invocation state");
			break;

		case 'p':
			result->passphrase =
			    strndup_or_exit(optarg, LONGEST_VALID_PASSPHRASE,
			                    "passphrase in invocation state");
			break;

		case 'm':
			result->mixin =
			    strdup_or_exit(optarg, "mixin data in invocation state");
			break;

		case 'k':
			switch (LOWERCASE(optarg[0])) {
			case 'l':
				result->kdf_hardness = kdf_hardness_low;
				break;
			case 'm':
				result->kdf_hardness = kdf_hardness_medium;
				break;
			case 'h':
				result->kdf_hardness = kdf_hardness_high;
				break;
			default:
				result->kdf_hardness = kdf_hardness_invalid;
				break;
			}
			break;

		case 'o':
			result->obfuscate_device_info = true;
			break;

		case 'h':
			result->subcommand = subcommand_help;
			break;

		default:
			invalid_invocation = true;
			break;
		}
	}

	if (result->subcommand == subcommand_unknown && optind < argc) {
		if (strcmp(argv[optind], "help") == 0) {
			result->subcommand = subcommand_help;
		} else if (strcmp(argv[optind], "enrol") == 0) {
			result->subcommand = subcommand_enrol;
		} else if (strcmp(argv[optind], "generate") == 0) {
			result->subcommand = subcommand_generate;
		}
	}

	// Add 1 to optind to take account of the subcommand, if we've already seen
	// it
	optind += (result->subcommand == subcommand_unknown) ? 0 : 1;
	int extra_args = argc - optind;

	if (extra_args > 0) {
		char *program_name = strrchr(argv[0], '/');
		if (program_name == NULL || program_name[1] == (char)0) {
			program_name = argv[0];
		} else {
			program_name += 1;
		}
		fprintf(stderr, "%s: unrecognized argument%s -- ", program_name,
		        extra_args > 1 ? "s" : "");

		for (int i = optind; i < argc; i++) {
			fprintf(stderr, "'%s'%s", argv[i], i < (argc - 1) ? " " : "\n");
		}

		invalid_invocation = true;
	}

	// Required arguments
	switch (result->subcommand) {
	case subcommand_enrol:
		invalid_invocation = invalid_invocation || result->device == NULL ||
		                     result->file == NULL || result->mixin != NULL ||
		                     result->kdf_hardness == kdf_hardness_invalid;
		break;
	case subcommand_generate:
		invalid_invocation = invalid_invocation || result->device != NULL ||
		                     result->file == NULL ||
		                     result->obfuscate_device_info ||
		                     result->kdf_hardness != kdf_hardness_unspecified;
		break;
	case subcommand_enumerate:
	case subcommand_help:
	case subcommand_version:
	default:
		invalid_invocation = invalid_invocation || result->device != NULL ||
		                     result->file != NULL || result->mixin != NULL ||
		                     result->passphrase != NULL ||
		                     result->obfuscate_device_info ||
		                     result->kdf_hardness != kdf_hardness_unspecified;
		break;
	}

	if (result->subcommand != subcommand_help && invalid_invocation) {
		free_invocation(result);
		print_usage(argv[0]);
		exit(EXIT_BAD_INVOCATION);
	}

	if (result->subcommand == subcommand_enrol &&
	    result->kdf_hardness == kdf_hardness_unspecified) {
		long pages = sysconf(_SC_PHYS_PAGES);
		long page_size = sysconf(_SC_PAGE_SIZE);
		size_t available_memory = pages * page_size;
		if (available_memory > (crypto_pwhash_MEMLIMIT_SENSITIVE * 2)) {
			result->kdf_hardness = kdf_hardness_high;
		} else if (available_memory > (crypto_pwhash_MEMLIMIT_MODERATE * 2)) {
			result->kdf_hardness = kdf_hardness_medium;
		} else {
			result->kdf_hardness = kdf_hardness_low;
		}
	}

	if (result->passphrase == NULL &&
	    (result->subcommand == subcommand_enrol ||
	     result->subcommand == subcommand_generate)) {
		result->passphrase =
		    malloc_or_exit(LONGEST_VALID_PASSPHRASE + 1, "passphrase");

		if (isatty(STDIN_FILENO)) {
			struct termios terminal_settings;
			if (tcgetattr(STDIN_FILENO, &terminal_settings) != 0) {
				err(EXIT_UNABLE_TO_GET_PASSPHRASE, "Unable to get passphrase");
			}
			tcflag_t previous_c_lflag = terminal_settings.c_lflag;
			terminal_settings.c_lflag &= ~(ECHO | ECHOE | ECHOK);
			terminal_settings.c_lflag |= ECHONL;
			if (tcsetattr(STDIN_FILENO, TCSANOW, &terminal_settings) != 0) {
				err(EXIT_UNABLE_TO_GET_PASSPHRASE, "Unable to get passphrase");
			}
			fprintf(stderr, "Passphrase: ");
			if (fgets(result->passphrase, LONGEST_VALID_PASSPHRASE, stdin) ==
			    NULL) {
				errx(EXIT_UNABLE_TO_GET_PASSPHRASE,
				     "Unable to get passphrase on STDIN: fgets error 0x%02x",
				     ferror(stdin));
			}

			// Remove trailing \n
			if (result->passphrase[strlen(result->passphrase) - 1] ==
			    NL_CHARACTER_TO_STRIP) {
				result->passphrase[strlen(result->passphrase) - 1] = 0x00;
			}

			// Reset settings
			terminal_settings.c_lflag = previous_c_lflag;
			if (tcsetattr(STDIN_FILENO, TCSANOW, &terminal_settings) != 0) {
				err(EXIT_UNABLE_TO_GET_PASSPHRASE,
				    "Unable to reset terminal after getting passphrase");
			}
		} else if (errno == ENOTTY) {
			if (fgets(result->passphrase, LONGEST_VALID_PASSPHRASE, stdin) ==
			    NULL) {
				errx(EXIT_UNABLE_TO_GET_PASSPHRASE,
				     "Unable to get passphrase on STDIN: fgets error 0x%02x",
				     ferror(stdin));
			}
		} else {
			err(EXIT_UNABLE_TO_GET_PASSPHRASE, "Unable to get passphrase");
		}
	}

	return result;
}

void free_invocation(invocation_state_t *invocation) {
	if (invocation == NULL) {
		return;
	}

	if (invocation->passphrase != NULL) {
		sodium_memzero(invocation->passphrase, strlen(invocation->passphrase));
		free(invocation->passphrase);
	}

	if (invocation->mixin != NULL) {
		free(invocation->mixin);
	}

	if (invocation->device != NULL) {
		free(invocation->device);
	}

	if (invocation->file != NULL) {
		free(invocation->file);
	}

	free(invocation);
}
