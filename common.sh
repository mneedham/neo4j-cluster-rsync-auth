#!/bin/bash

if [ -z "$NEO4J_VERSION" ] ; then
  echo "No NEO4J_VERSION set"
  exit -1
fi

if [ -z "$NEO4J_PASSWORD" ] ; then
  echo "No NEO4J_PASSWORD set"
  exit -1
fi

export NEO4J_TEMPLATE="neo4j-enterprise-$NEO4J_VERSION"

if [ ! -d "$NEO4J_TEMPLATE" ] ; then
  echo "No Neo4j template directory found: $NEO4J_TEMPLATE"
  exit -1
fi

if [ -z "$NUMBER_CORES" ] ; then
  export NUMBER_CORES=3
  echo "Setting NUMBER_CORES to default: $NUMBER_CORES"
fi

if [ -z "$NUMBER_EDGES" ] ; then
  export NUMBER_EDGES=0
  echo "Setting NUMBER_EDGES to default: $NUMBER_EDGES"
fi

function installCluster() {
  prefix=$1
  typeset -i i END # Let's be explicit
  let END=$2
  for ((i=1;i<=END;++i)); do
    dir="${prefix}_${i}"
    if [ -d "$dir" ] ; then
      echo "Directory already exists: $dir"
      echo "Stopping previous installation"
      $dir/bin/neo4j stop
    else
      echo "Installing $dir"
      mkdir -p $dir
      cp -a $NEO4J_TEMPLATE/* $dir/
      $dir/bin/neo4j-admin set-initial-password $NEO4J_PASSWORD
    fi
  done
}

function deleteCluster() {
  prefix=$1
  typeset -i i END # Let's be explicit
  let END=$2
  for ((i=1;i<=END;++i)); do
    dir="${prefix}_${i}"
    if [ -d "$dir" ] ; then
      rm -Rf $dir
    else
      echo "Directory does not exist: $dir"
    fi
  done
}

function printConfigFromPatch() {
  conf_patch=$1
  echo -e "\tConfig settings changed:"
  for line in `grep -v 'neo4j.conf' $conf_patch | grep -e '^\+'`
  do
    echo -e "\t\t${line:1}"
  done
}

function configureCluster() {
  prefix=$1
  ce_mode=$(echo "$prefix" | tr '[:lower:]' '[:upper:]')
  typeset -i i END # Let's be explicit
  let END=$2
  for ((i=1;i<=END;++i)); do
    dir="${prefix}_${i}"
    if [ -d "$dir" ] ; then
      echo "Configuring $dir"
      mkdir -p $dir/conf
      cp -a $NEO4J_TEMPLATE/conf/neo4j.conf $dir/conf/
      conf_patch="neo4j.conf.${prefix}_${instance}.patch"
      echo -e "\tMaking patch for ${prefix}_${i} in $conf_patch"
      cat neo4j.conf.patch \
        | sed -e "s/^\+\(.*\)1$/\+\1$i/" \
        | sed -e "s/^\+dbms.mode=CORE$/\+dbms.mode=$ce_mode/" \
        > $conf_patch
      if [ -f "$conf_patch" ] ; then
        echo -e "\tPatching $dir/conf/neo4j.conf"
        patch -s -i $conf_patch $dir/conf/neo4j.conf
        printConfigFromPatch $conf_patch
      else
        echo "No such file: $conf_patch"
      fi
    else
      echo "Directory does not exist: $dir"
    fi
  done
}

function makeClusterConfigLocal() {
  cp -a cluster.config cluster.config.local
  rm -f crontab.local
  touch crontab.local
  logfile="$(pwd)/cluster_rsync.log"
  prefix=$1
  typeset -i i END # Let's be explicit
  let END=$2
  for ((i=1;i<=END;++i)); do
    dir="${prefix}_${i}"
    path="$(pwd)/${dir}"
    address="${USER}@localhost"
    if [ -d "$dir" ] ; then
      echo "Making cluster config for $dir using address $address and path $path"
      echo "$dir    $address    $path" >> cluster.config.local
      echo "* * * * *    $path/bin/rsync_auth.sh >> $logfile" >> crontab.local
    else
      echo "Directory does not exist: $dir"
    fi
  done
}

function configureClusterRSync() {
  prefix=$1
  typeset -i i END # Let's be explicit
  let END=$2
  for ((i=1;i<=END;++i)); do
    dir="${prefix}_${i}"
    path="$(pwd)/${dir}"
    if [ -d "$dir" ] ; then
      echo "Configuring cluster rsync for installation at $dir"
      mkdir -p $dir/conf
      cp -a cluster.config.local $dir/conf/cluster.config
      cp -a rsync_auth.sh $dir/bin/
    else
      echo "Directory does not exist: $dir"
    fi
  done
  if [ -f "crontab.local" ] ; then
    echo "Installing crontab"
    crontab crontab.local
  else
    echo "No crontab.local found"
  fi
  crontab -l
}

function clearCluster() {
  prefix=$1
  typeset -i i END # Let's be explicit
  let END=$2
  for ((i=1;i<=END;++i)); do
    dir="${prefix}_${i}"
    if [ -d "$dir" ] ; then
      echo "Clearing logs and graph.db for $dir"
      rm -f $dir/logs/* $dir/data/databases/graph.db
    else
      echo "Directory does not exist: $dir"
    fi
  done
}

function waitForCluster() {
  prefix=$1
  typeset -i i END # Let's be explicit
  let END=$2
  for ((i=1;i<=END;++i)); do
    http_port="748${i}"
    end="$((SECONDS+20))"
    echo -en "\tWaiting for response at port $http_port "
    rc=0
    while true; do
        [[ "200" = "$(curl --silent --write-out %{http_code} --output /dev/null http://localhost:$http_port)" ]] && break
        [[ "${SECONDS}" -ge "${end}" ]] && rc=1 && break
        echo -n "."
        sleep 1
    done
    echo
    if [ $rc ] ; then
      echo -e "\tInstance ${prefix}_${i} is up"
    else
      echo -e "\tTimed out waiting for ${prefix}_${i} to respond"
    fi
  done
}

function clusterCommand() {
  command=$1
  prefix=$2
  typeset -i i END # Let's be explicit
  let END=$3
  for ((i=1;i<=END;++i)); do
    dir="${prefix}_${i}"
    if [ -x "$dir/bin/neo4j" ] ; then
      echo "S${command:1}ing Neo4j $NEO4J_VERSION in $dir"
      $dir/bin/neo4j $command
    else
      echo "Command is not executable: $dir/bin/neo4j"
    fi
  done
}

function startCluster() {
  clusterCommand "start" $@
}

function stopCluster() {
  clusterCommand "stop" $@
}
