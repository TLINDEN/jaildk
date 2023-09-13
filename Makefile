JAILDIR=/jail

all:
	bash bin/bash-completor -c src/completions.sh
	grep -B10 COMPLETIONCODE src/jaildk.sh | grep -v COMPLETIONCODE > jaildk
	cat src/_jaildk-completion.bash >> jaildk
	grep -A 10000 COMPLETIONCODE src/jaildk.sh | grep -v COMPLETIONCODE >> jaildk
	rm -f src/_jaildk-completion.bash

install:
	sh jaildk setup $JAILDIR

clean:
	rm -f jaildk
