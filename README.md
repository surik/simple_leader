# simple_leader

Echo interview task(www.echorussia.ru/jobs/serverside-june-2013.html).
   
### Usage

Build:

    $ git clone https://github.com/surik/simple_leader.git
    $ cd simple_leader
    $ rebar get-deps compile

Edit leader.config:

    * Add nodes in leader section.
    * Set timeout.
    * Set log level in lager section.

and then:

    $ ./start.sh 1
    $ ./start.sh 2
    ...

Kill the node and see logs.
