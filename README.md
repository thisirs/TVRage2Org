# TVRage2Org

TVRage2Org is a ruby script that automatically fetches your favourite
shows on [TVRage](http://www.tvrage.com) and make it into an
[Org](http://orgmode.org) file to be part of your agenda files. You
have something like that:

![agenda screenshot](images/agenda.png)

Your favourite shows are stored in a
[Yaml](http://en.wikipedia.org/wiki/YAML) file. See
[config.yaml](config.yaml) for an example.

## Examples

Custom configuration file, no debug messages and results in an org file:

    ruby main.rb -f myconfigfile.yaml 2> /dev/null > ~/Org/series.org

Same thing with the -o option:

    ruby main.rb -f myconfigfile.yaml -o ~/Org/series.org

This script is likely to be run by a cron task. As an example, I
place the bash script [TVrage2org](TVrage2org) in /etc/cron.daily/.
