all:
	bash bin/bash-completor -c completions.sh
	echo "JAILDIR=/jail" > jaildk-completion.bash
	cat _jaildk-completion.bash >> jaildk-completion.bash
	rm -f _jaildk-completion.bash
