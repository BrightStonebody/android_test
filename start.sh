#!/bin/bash

export illegalUserException=99
export syncClientExecException=100
export killNotAllowException=101
export pullFailureException=102
export revertCodeException=103
export rsyncException=104
export buildFailureException=105

source .remoteX/code/local/utils.sh
source .remoteX/code/local/utils_inc_install.sh
source .remoteX/code/local/data_collect.sh
source .remoteX/code/local/data_collect_hermes.sh
source .remoteX/code/local/checkUpgrade.sh
source .remoteX/code/local/trycatch.sh
source .remoteX/code/local/error_handle.sh
source .remoteX/code/local/rsync_opt.sh
source .remoteX/code/local/local_apk_patch.sh
source .remoteX/code/local/preload_apk_opt.sh

if [ "$1" == "--version" ] || [ "$1" == "-V" ]; then
  VERSION=$(cat .remoteX/code/local/data_collect.sh | grep "VERSION=" | cut -d '=' -f2 | sed 's/\"//g')
  FLAVOR_TYPE=$(cat .remoteX/code/local/data_collect.sh | grep "FLAVOR_TYPE=")
  if [ -n "$FLAVOR_TYPE" ]; then
    echo "RemoteX version $VERSION cloud_workspace architecture"
  else
    echo "RemoteX version $VERSION old architecture"
  fi
  exit 0
fi

if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  echoHelp
  exit 0
fi

# check release status with git and user
if [ "$1" == "selfUpdated" ]; then
  eval set -- ${@:2}
else
  tryToRunSelfUpdate $@
fi

# 异步执行mira检测脚本
MIRA_SH="./tools/mira_tools/mira.sh"
if [ -f $MIRA_SH ]; then
  mkdir -p .mira_tools
  chmod +x $MIRA_SH && $MIRA_SH $@ &>.mira_tools/log.txt &
fi

echo "===================================================================================="
echo "===================== Welcome To RemoteX By Client Infrastructure-DevOps ==========="
echo "===================================================================================="
echo ""

START_TIME="$(date +%s)"

echoHelp
writeLocalProjectDir

PROJECT_DIR="$(pwd)"
PROJECT_PARENT_DIR="$(dirname "$PROJECT_DIR")"
LOCAL_WORK_DIR="$PROJECT_DIR/.remoteX/code"
LOCAL_WORK_DIR_CUSTOM="$PROJECT_DIR/.remoteX/custom"
SAVED_USER_COMMAND=$@

function readConfigProperty() {
  grep "^${1}=" "$LOCAL_WORK_DIR/remote_machine_info" | cut -d'=' -f2
}

function mainRepoRelativePath() {
  local androidRepoRelativePath=$(readGlobalProperty 'remoteX.android.repo.relative.path')
  if [ -n "$androidRepoRelativePath" ]; then
    echo $androidRepoRelativePath
  fi
}

function stopUserBuild() {
  COMMAND=" chmod +x .remoteX/code/local/killGradleDaemon.sh && .remoteX/code/local/killGradleDaemon.sh $USER_EMAIL  "
  ignoreErrors
  execCmdToRemote "$REMOTE_DIR" "$COMMAND"
  echo ""
  echo "Stop Success"
  exit 0
}

function handleTrap() {
  echo "用户取消编译，结束用户远程的编译中...."
  # Hermes 用户在增量包生效时，有可能会终止 APK 构建
  # 因此在用户终止 APK 编译的时候，判断如果增量包编译成功（编译时间大于0），也上报数据
  initHermesCompileTime $PROJECT_DIR $HERMES_START_TIME
  if [ $HERMES_COMPILE_TIME -gt 0 ]; then
    # 用户终止 APK 编译
    APK_COMPILE_STATUS=2
    collectHermesDataToVision &>/dev/null
  fi

  TAG=$(addTag "$TAG" "user_interrupt_compilation")
  collectData &>/dev/null
  stopUserBuild
}

function pullCodeGen() {
  PULL_DIR=$1

  if [ -z "$PULL_DIR" ]; then
    mkdir -p build
    set +e

    #pull switch.local.yml
    pullFileOrDir -f switch.local.yml $RSYNC_SERVER $ANDROID_REPO_NAME $PROJECT_DIR / >/dev/null 2>&1
    #pull pack res
    pullFileOrDir -f build/packRes.zip $RSYNC_SERVER $ANDROID_REPO_NAME $PROJECT_DIR build/ >/dev/null 2>&1
  else
    for PULL_DIR in "$@"; do
      echo "pull project path is: $PULL_DIR"
      pullFileOrDir -f $PULL_DIR/ $RSYNC_SERVER $ANDROID_REPO_NAME $PROJECT_DIR "$PULL_DIR/" >/dev/null 2>&1
      echo ""
    done
  fi

  if [ $? != 0 ]; then
    echo ""
    echo "[31mpull code gen source failure!!! [0m"
    exit 1
  else
    if [ -z "$PULL_DIR" ]; then
      unzip -o build/packRes.zip -d ./
    fi
    echo ""
    echo "[32mPull code gen success [0m"
    exit 0
  fi
}

function pullAndReadApkDirFromFile() {
  if [ ! -d "build" ]; then
    mkdir build
  fi
  # pull & read gradle generated apk_path file
  local path_file="apk_dir_path.txt"
  pullFileOrDir -f $path_file $RSYNC_SERVER $ANDROID_REPO_NAME $PROJECT_DIR build/ >/dev/null 2>&1
  if [ $? == 0 ]; then
    if [ -f "build/$path_file" ]; then
      local apk_dir_path=$(cat "build/$path_file")
      echo "$apk_dir_path"
    fi
  fi
}

function tryInstallLocalApk() {
  local apk_path=$1
  local path_file="apk_dir_path.txt"
  if [ -z "$apk_path" ]; then
    if [ -f "$LOCAL_WORK_DIR_CUSTOM/apk_path.txt" ]; then
      apk_path=$(readCustomApkPath "$LOCAL_WORK_DIR_CUSTOM/apk_path.txt")
      #echo "apk_path.txt: $apk_path"
    fi

    if [ -z "$apk_path" ]; then
      if [ -f "build/$path_file" ]; then
        apk_path=$(cat "build/$path_file")
        #echo "build/: $apk_path"
      fi
    fi
  fi
  installAndLaunchApk $apk_path
}

function generateSyncRepoParam() {
  local command
  # 主仓 .remoteX/custom/rsync_local_include_file.txt 文件
  if [ -f "$LOCAL_WORK_DIR_CUSTOM/rsync_local_include_file.txt" ]; then
    command+=" --include-from='$LOCAL_WORK_DIR_CUSTOM/rsync_local_include_file.txt' "
  fi
  # 主仓 .remoteX/custom/rsync_local_ignore_file.txt 文件
  if [ -f "$LOCAL_WORK_DIR_CUSTOM/rsync_local_ignore_file.txt" ]; then
    command+=" --exclude-from='$LOCAL_WORK_DIR_CUSTOM/rsync_local_ignore_file.txt' "
  fi
  # 主仓主 ignore 文件 .remoteX/code/rsync_local_ignore_file.txt
  if [ -f "$LOCAL_WORK_DIR/rsync_local_ignore_file.txt" ]; then
    command+=" --exclude-from='$LOCAL_WORK_DIR/rsync_local_ignore_file.txt' "
  fi
  echo $command
}

function syncRepoInParallel() {
  local repoList=("$@")
  local homeDir="$HOME/.remoteX"
  if [ ! -d "$homeDir" ]; then
    mkdir -p $homeDir
  fi

  _fifofile="$homeDir/$$.fifo"
  mkfifo $_fifofile  # 创建一个FIFO类型的文件
  exec 6<>$_fifofile # 将文件描述符6写入 FIFO 管道， 这里6也可以是其它数字
  rm -rf $_fifofile  # 删也可以，

  degree=5 # 定义并行度

  # 根据并行度设置信号个数
  # 事实上是在fd6中放置了$degree个回车符
  local i
  for ((i = 0; i < ${degree}; i++)); do
    echo
  done >&6

  local startTime="$(date +%s)"
  local pids=()
  local repo
  for repo in "${repoList[@]}"; do
    # 从管道中读取（消费掉）一个字符信号
    # 当FD6中没有回车符时，停止，实现并行度控制
    read -u6
    {
      if [ "$repo" == "main" ]; then
        syncMainRepoByCache "${repoList[@]}"
      else
        syncSubRepo $repo
      fi
      echo >&6 # 当进程结束以后，再向管道追加一个信号，保持管道中的信号总数量
    } &
    pids+=($!)
  done
  # wait for all pids
  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  exec 6>&- # 关闭管道
  TIME_RSYNC_DIFF_SUB_REPO="$(($(date +%s) - startTime))"
}

function syncFileMeta() {
  local fileMetaPath=$1
  local command=$(genRsyncLocalToRemoteCommand "$RSYNC_SERVER" "$PROJECT_DIR/$fileMetaPath" "logs")
  local logFile=$(getRsyncLogFile)
  echo ""
  rLogger "increment sync file attr → remote machine (增量同步文件属性): $PROJECT_DIR/$fileMetaPath" true
  doRsync "$command" | tee -a "$logFile"
}

function syncMainRepo() {
  ## rsync 同步主仓及子仓代码
  local mainRepoDir="$PROJECT_DIR"
  if [ -n "$MAIN_REPO_RELATIVE_PATH" ]; then
    mainRepoDir=${PROJECT_DIR%/$MAIN_REPO_RELATIVE_PATH}
  fi
  local command=$(genRsyncLocalToRemoteCommand "$RSYNC_SERVER" "$mainRepoDir/" "$MAIN_REPO_NAME/")
  command+=" $(generateSyncRepoParam)"
  echo ""
  rLogger "increment sync main repo  →  remote machine （增量同步主仓文件）：$PROJECT_DIR " true
  local logFile=$(getRsyncLogFile)
  doRsync "$command" | tee -a "$logFile"
}

function syncMainRepoInParallel() {
  local repoSize="$1"
  local bigDirIndexFile=$(getRepoBigDirIndex)
  if [ -z "$bigDirIndexFile" ] || [ ! -s "$bigDirIndexFile" ]; then
    return 1
  fi

  local _fifofile="main-repo-$$.fifo"
  mkfifo $_fifofile
  exec 7<>$_fifofile
  rm -rf $_fifofile

  degree=10
  if [ "$repoSize" -gt 1 ]; then
    degree=$((degree - $repoSize + 1))
  fi
  for ((i = 0; i < ${degree}; i++)); do
    echo >&7
  done

  bigDirList=()
  for line in $(cat "$bigDirIndexFile"); do
    bigDirList+=("$line")
  done

  local mainRepoDir="$PROJECT_DIR"
  if [ -n "$MAIN_REPO_RELATIVE_PATH" ]; then
    mainRepoDir=${PROJECT_DIR%/$MAIN_REPO_RELATIVE_PATH}
  fi

  local command
  local element
  local logFile=$(getRsyncLogFile)
  local pids=()
  bigDirList+=("main-repo")
  for element in "${bigDirList[@]}"; do
    read -u7
    {
      if [ "$element" == "main-repo" ]; then
        # 同步剩余目录
        command=$(genRsyncLocalToRemoteCommand "$RSYNC_SERVER" "$mainRepoDir/" "$MAIN_REPO_NAME/")
        command+=" $(generateSyncRepoParam)"
        command+=" --exclude-from='$bigDirIndexFile'"
        echo ""
        rLogger "increment sync main repo  →  remote machine （增量同步主仓）：$mainRepoDir " true
        doRsync "$command" | tee -a "$logFile"
      else
        if [ -e "${mainRepoDir}/${element}" ]; then
          command=$(genRsyncLocalToRemoteCommand "$RSYNC_SERVER" "${mainRepoDir}/${element}" "${MAIN_REPO_NAME}/${element}")
          command+=" $(generateSyncRepoParam)"
          rLogger "increment sync main repo  →  remote machine （增量同步主仓-${element}）：${mainRepoDir}/${element} " true
          doRsync "$command" | tee -a "$logFile"
        fi
      fi
      echo >&7
    } &
    pids+=($!)
  done

  # wait for all pids
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
  exec 7>&-
  TAG=$(addTag "$TAG" "upload_parallel_enable=true")
}

function syncMainRepoByCache() {
  local repoList=("$@")
  local rsyncOpt=false
  local retCode=0
  local startTime="$(date +%s)"
  if [ "$IS_INCREMENTAL" == false ] || ! canUseCache; then
    rLogger "sync main repo fully! IS_INCREMENTAL: $IS_INCREMENTAL"
    syncMainRepoInParallel "${#repoList[@]}"
    retCode=$?
    deleteWatchCacheIfExist
  else
    echo ""
    local hint="sync main repo changed files  →  remote machine (同步本地修改文件): "
    echo "$hint"
    rLogger "$hint"
    if syncCache; then
      rsyncOpt=true
      rLogger "syncCache rsync successfully!"
    else
      logColorWarn "[warning] sync changed cache files of main repo failed! fallback to full sync..."
      rLogger "syncCache rsync failed! fallback to full sync."
      syncMainRepoInParallel "${#repoList[@]}"
      retCode=$?
      deleteWatchCacheIfExist
    fi
  fi

  if [ $retCode != 0 ]; then
    #rLogger "increment sync main repo in parallel failed! rolling back to direct sync." true
    syncMainRepo
  fi
  echo "$rsyncOpt" >"$MAIN_REPO_DIFF_OPT"
  costTime="$(($(date +%s) - startTime))"
  echo "$costTime" >build/sync_main_repo_time
}

function syncSubRepo() {
  # 同步子仓
  local repoName=$1
  if [[ $repoName == */ ]]; then
    repoName=$(echo "$repoName" | sed 's/\/$//')
  fi
  if [[ $repoName == */* ]]; then
    local realRepoName=${repoName##*/}
    if [[ "$repoName" != */ ]]; then
      repoName="$repoName/"
    fi
    local command=$(genRsyncLocalToRemoteCommand "$RSYNC_SERVER" "$repoName" "$realRepoName/")
  else
    local command=$(genRsyncLocalToRemoteCommand "$RSYNC_SERVER" "$PROJECT_PARENT_DIR/$repoName/" "$repoName/")
  fi
  command+=" $(generateSyncRepoParam)"
  echo ""
  rLogger "increment rsync sub repo  →  remote machine （增量同步子仓文件）： $PROJECT_PARENT_DIR/$repoName " true
  local logFile=$(getRsyncLogFile)
  doRsync "$command" | tee -a "$logFile"
}

function operateWorkspace() {
  local operation=$1
  .remoteX/code/local/remoteXClient.sh "none" >/dev/null
  port=$(cat $HOME/.remoteX/port_$BUILD_TYPE.txt)
  result=$(curl --connect-timeout 2 -sS -X POST -H "Content-Type: application/json" http://127.0.0.1:$port/workspace \
    -d '{"repoUrl":"'$(readConfigProperty "repoUrl")'", "workingDir":"'$PROJECT_DIR'", "email":"'$(readConfigProperty "user")'", "wsid":"'$(readConfigProperty "wsid")'", "operation":"'$operation'"}')
  echo $result
}

function collectRsyncError() {
  local rsync_fail_code=$1
  local rsync_fail_cause=$2
  local operation="rsync"
  .remoteX/code/local/remoteXClient.sh "none" >/dev/null
  port=$(cat $HOME/.remoteX/port_$BUILD_TYPE.txt)
  body="
    {
      \"email\":\"$(readConfigProperty 'user')\",
      \"repoUrl\":\"$(readConfigProperty 'repoUrl')\",
      \"wsid\":\"$(readConfigProperty 'wsid')\",
      \"machine_server\":\"$(readConfigProperty 'machineServer')\",
      \"rsync_proxy\":\"$(readConfigProperty 'rsyncProxy')\",
      \"rsync_server\":\"$(readConfigProperty 'rsyncServer')\",
      \"host_ip\":\"$(readConfigProperty 'hostIp')\",
      \"workingDir\":\"$PROJECT_DIR\",
      \"operation\":\"$operation\",
      \"rsync_fail_code\":$rsync_fail_code,
      \"rsync_fail_cause\":\"$rsync_fail_cause\"
    }
  "
  curl --connect-timeout 2 -s -o /dev/null -X POST -H "Content-Type: application/json" http://127.0.0.1:$port/workspace -d "$body"
}

function checkWSStatus() {
  local wsid=$(readConfigProperty "wsid")
  local waitStep=1
  while true; do
    isSlept=$(operateWorkspace "isSlept")
    if [ "$isSlept" == "no" ] && [ $waitStep -le 10 ]; then
      code=1
      sleep 1
      let waitStep++
    else
      code=0
      break
    fi
  done
  return $code
}

function execCmdToRemote() {
  execCommandWithRPC "$MACHINE_SERVER" "$BUILD_TYPE" "$USER_EMAIL" "$REPO_GIT_URL" "$WORKSPACE_ID" "$1" "\"$2\""
  local code=$?
  if [ $code == 100 ]; then
    logColorError "[error] 检测到编译进程状态异常，正在重新触发命令中..."
    ps -ef | grep sync-client | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {}
    .remoteX/code/local/remoteXClient.sh "none" >/dev/null
    execCommandWithRPC "$MACHINE_SERVER" "$BUILD_TYPE" "$USER_EMAIL" "$REPO_GIT_URL" "$WORKSPACE_ID" "$1" "\"$2\""
    code=$?
  fi
  return $code
}

function copyWorkspaceFile() {
  local buildType
  local wsid
  local srcPath
  local destPath

  if [ $# -eq 2 ]; then
    buildType="$BUILD_TYPE"
    wsid=$(readConfigProperty "wsid")
    srcPath="$1"
    destPath="$2"
  elif [ $# -eq 3 ]; then
    buildType="$BUILD_TYPE"
    wsid="$1"
    srcPath="$2"
    destPath="$3"
  elif [ $# -eq 4 ]; then
    buildType="$1"
    wsid="$2"
    srcPath="$3"
    destPath="$4"
  else
    logColorError ""
    logColorError "copy failed! input params illegal!"
    logColorInfo ""
    logColorInfo "Usage: "
    logColorInfo "拉当前工程远端的文件：./start.sh workspace copy srcPath destPath"
    logColorInfo "拉其他人远端的文件：./start.sh workspace copy wsid srcPath destPath"
    logColorInfo ""
  fi
  bash "$LOCAL_WORK_DIR/local/ws_client.sh" "copy" "$buildType" "$wsid" "$srcPath" "$destPath"
}

function getMetaFileName() {
  local port=$(cat $HOME/.remoteX/port_$BUILD_TYPE.txt)
  local metaFileName=$(curl --connect-timeout 10 -s -X POST -d $PROJECT_DIR http://127.0.0.1:$port/fileMeta/name 2>/dev/null)
  if [ $? == 0 ]; then
    echo "$metaFileName"
  fi
}

function collectMetaFileInfo() {
  echo ""
  logColorInfo ">>>>>> start to collect local file meta info... <<<<<<"
  startTime="$(date +%s)"
  port=$(cat $HOME/.remoteX/port_$BUILD_TYPE.txt)
  metaFileName=$(curl --connect-timeout 10 -s -X POST -d $PROJECT_DIR http://127.0.0.1:$port/fileMeta/collect)
  costTime="$(($(date +%s) - startTime))"

  metaFilePath="build/${metaFileName}"
  #logColorInfo "local file meta info: $metaFilePath"
  #logColorInfo ">>>>>> collect local file meta info end! cost: ${costTime}s <<<<<<"
  echo "$costTime" >build/collect_meta_file_time
}

# 云端 patch 方案
# 埋点数据：是否是增量拉取、Patch 包大小、拉 Patch 包耗时、安装 Patch 包耗时
function makeAndPullApkPatch() {
  canUsePatch
  code=$?
  if [ $code -ne 0 ]; then
    if [ $code == 2 ]; then
      TAG=$(addTag "$TAG" "apk_opt_enable=false")
    fi
    echo "disable apk patch opt....:("
    return 1
  fi
  IS_INCREMENTAL_RSYNC=true
  IS_USED_APK_PATCH_OPT=true
  local apkInfoFile="build/deploy/apk_info.txt"
  if [ -s "$apkInfoFile" ]; then
    phoneApkPath=$(sed -n '1p' "$apkInfoFile")
    packageName=$(sed -n '2p' "$apkInfoFile")
    phoneApkMd5=$(sed -n '3p' "$apkInfoFile")
  fi

  if [ -z "$phoneApkPath" ]; then
    phoneApkPath=$(getPhoneApkPath "$packageName")
    if [ -z "$phoneApkPath" ]; then
      APK_PATCH_OPT_FAIL_REASON="cannot get the phone apk path, device: $(getDeviceInfo)"
      return 1
    fi
  fi
  if [ -z "$phoneApkMd5" ]; then
    phoneApkMd5=$(getApkMd5 "$phoneApkPath")
    if [ -z "$phoneApkMd5" ]; then
      APK_PATCH_OPT_FAIL_REASON="cannot get the phone apk md5"
      return 1
    fi
  fi

  # 先校验本地 dump 数据
  dumpFlagFile="build/deploy/dump_apk_flag.txt"
  if [ -s "$dumpFlagFile" ]; then
    dumpPhoneApkPath=$(cat "$dumpFlagFile")
    echo "dumpPhoneApkPath: $dumpPhoneApkPath, phoneApkPath: $phoneApkPath"
    if [[ -n "$dumpPhoneApkPath" && "$dumpPhoneApkPath" == "$phoneApkPath" ]]; then
      # rsync dump file
      COMMAND=$(genRsyncLocalToRemoteCommand "$RSYNC_SERVER" "$PROJECT_DIR/build/deploy/dump_apk.bin $PROJECT_DIR/build/deploy/dump_apk_flag.txt" ".patch")
      doRsync "$COMMAND"
      apkDumpResult=true
    fi
  fi

  execCmdToRemote "$REMOTE_DIR" "source .remoteX/code/local/remote_apk_patch.sh && makePatch $phoneApkPath $phoneApkMd5 $apkDumpResult"
  if [ $? -ne 0 ]; then
    echo "make apk patch failed!"
    # 读取远端 error file 获取具体错误原因
    COMMAND="errorFile=.patch/patch_error.txt && [ -f \$errorFile ] && cat \$errorFile && rm -rf \$errorFile"
    reason=$(execCmdToRemote "$REMOTE_DIR" "$COMMAND")
    if [ -z "$reason" ]; then
      reason="make apk patch on remote failed"
    fi
    APK_PATCH_OPT_FAIL_REASON="$reason"
    return 1
  fi

  local startTime="$(date +%s)"
  pullPatch
  code=$?
  TIME_PULL_APK="$(($(date +%s) - startTime))"
  echo "Sync APK Patch Time(耗时): $(formatTime $TIME_PULL_APK)"
  echo ""
  if [ $code -ne 0 ]; then
    echo "failed to pull patch from remote to local build dir"
    APK_PATCH_OPT_FAIL_REASON="pull apk patch failed"
    return 1
  fi
  return 0
}

function pullApkWithHint() {
  local isStatData=$1
  if [ -z "$isStatData" ]; then
    isStatData=true
  fi

  local startTime=$(date +%s)
  PULL_APK_DIR="$(dirname "$ANDROID_REPO_NAME/$LOCAL_APK_PATH")"
  COMMAND=$(genRsyncRemoteToLocalCommand "$RSYNC_SERVER" "$PULL_APK_DIR/" "$PROJECT_DIR/$LOCAL_APK_DIR/")
  apkSize=$(getLocalApkSize)
  if [ -n "$apkSize" ]; then
    COMMAND+=" --block-size=$(calRsyncBlockSize $apkSize)"
  fi
  echo "sync remote machine apk  →  to local dir （同步远程APK至本地）: $PROJECT_DIR/$LOCAL_APK_DIR/"
  rsyncLogFile="build/rsync_result_tmp"
  mkdir -p $(dirname $rsyncLogFile)
  doPullApk "$COMMAND" | tee "$rsyncLogFile"
  code=${PIPESTATUS[0]}
  if [ $code -ne 0 ]; then
    logColorError "[error] failed to pull the remote APK file!!! please check whether local network status or remote apk exists! (拉取远端 APK 失败，请检查本地网络或远端文件是否存在！远端链接：https://remotex.bytedance.net/workspace)"
    echo ""
  fi

  costTime=$(($(date +%s) - startTime))
  if [ $isStatData == true ]; then
    RSYNC_RESULT=$(cat $rsyncLogFile)
    # 过滤出receive数据量
    RECEIVED_BYTE_PATTERN='received ([0-9|,]+) bytes'
    [[ $RSYNC_RESULT =~ $RECEIVED_BYTE_PATTERN ]]
    RSYNC_OUTPUT_RECEIVED_BYTES=${BASH_REMATCH[1]//,/}

    # 过滤出原始Apk大小
    TOTAL_BYTE_PATTERN='total size is ([0-9|,]+)'
    [[ $RSYNC_RESULT =~ $TOTAL_BYTE_PATTERN ]]
    RSYNC_OUTPUT_TOTAL_BYTES=${BASH_REMATCH[1]//,/}
    TIME_PULL_APK=$costTime
  fi

  rm $rsyncLogFile
  echo "Sync APK time(耗时): $(formatTime $costTime)"
  echo ""
}

function getHummerBuildId() {
  local repoName="$1"
  local command="cd $repoName && cat build/byte_build_scan.id && rm -rf build/byte_build_scan.id"
  buildId=$(execCmdToRemote "$REMOTE_DIR" "$command")
  if [[ -n $buildId ]] && [[ $buildId =~ ^[0-9]+$ ]]; then
    echo "$buildId" >build/hummer_build_id.txt
  else
    echo "" >build/hummer_build_id.txt
  fi
}

GIT_TRACE_FILE="$LOCAL_WORK_DIR/local/git_trace.sh"
if [ -f "$GIT_TRACE_FILE" ]; then
  bash "$GIT_TRACE_FILE" >/dev/null 2>&1 &
fi

if [[ $1 == "update" ]]; then
  checkUpgradeWithoutGray
  if [ $? == 1 ]; then
    echo "No need to update, it is already the latest version!"
  fi
  exit 0
fi

if [[ $1 == "rollback" ]]; then
  echo "start switching back to the old architecture..."
  forceRollback
  echo "switch done!"
  exit 0
fi

if [[ $1 == "gray" ]]; then
  echo "start switching to the new architecture..."
  forceGray
  echo "switch done！welcome to use! see detail: https://bytedance.feishu.cn/docx/doxcnqPleRWRTeRQ52VdcKPCv7t"
  exit 0
fi

if [[ $1 == "install" ]]; then
  tryInstallLocalApk $2
  exit 0
fi

if [[ $1 == "openNotice" ]]; then
  writeOptionValue 'lark.notice.enabled' 'true'
  echo "open lark notice successfully!"
  exit 0
fi

if [[ $1 == "closeNotice" ]]; then
  writeOptionValue 'lark.notice.enabled' 'false'
  echo "close lark notice successfully!"
  exit 0
fi

if [[ $1 == "openRsyncOpt" ]]; then
  writeOptionValue 'rsync.opt.enabled' 'true'
  echo "open rsync opt successfully!"
  exit 0
fi

if [[ $1 == "closeRsyncOpt" ]]; then
  writeOptionValue 'rsync.opt.enabled' 'false'
  echo "close rsync opt successfully!"
  exit 0
fi

if [[ $1 == "openApkOpt" ]]; then
  writeOptionValue 'apk.opt.enabled' 'true'
  echo "open apk opt successfully!"
  exit 0
fi

if [[ $1 == "closeApkOpt" ]]; then
  writeOptionValue 'apk.opt.enabled' 'false'
  echo "close apk opt successfully!"
  exit 0
fi

if [[ $1 == "openGitxClean" ]]; then
  writeOptionValue 'remoteX.gitx.cleanup.enable' 'true'
  echo "open GitX clean opt successfully!"
  exit 0
fi

if [[ $1 == "closeGitxClean" ]]; then
  writeOptionValue 'remoteX.gitx.cleanup.enable' 'false'
  echo "close GitX clean opt successfully!"
  exit 0
fi

if [[ $1 == "dig" ]]; then
  echo "start to tar and upload log..."
  logLink=$(uploadRsyncLog)
  echo "log link: $logLink"
  exit 0
fi

if [[ $1 == "saveWorkspace" ]]; then
  currentDateTime=$(date "+%Y-%m-%d %H:%M:%S")
  echo "$currentDateTime" >"$LOCAL_WORK_DIR/saveWorkspace"
  echo "save workspace successfully!"
  exit 0
fi

if [[ $1 == "workspace" ]]; then
  if [[ $2 == "console" ]]; then
    wsid="${3:-$(readConfigProperty "wsid")}"
    bash "$LOCAL_WORK_DIR/local/ws_client.sh" "console" "$BUILD_TYPE" "$wsid"
  elif [[ $2 == "copy" ]]; then
    eval set -- ${@:3}
    copyWorkspaceFile "$@"
  elif [[ $2 == "cmd" ]]; then
    cmd="${@:3}"
    wsid=$(readConfigProperty "wsid")
    bash "$LOCAL_WORK_DIR/local/ws_client.sh" "cmd" "$BUILD_TYPE" "$wsid" "$cmd"
  else
    # webshell、delete...
    echo "workspace operation: $1 start, please wait..."
    operateWorkspace $2
  fi

  REPO_GIT_URL=$(readConfigProperty "repoUrl")
  REPO_USER_EMAIL=$(readConfigProperty "user")
  REMOTE_MACHINE_IP=$(readConfigProperty "hostIp")
  TAG=$(addTag "$TAG" "ws_operation=$2")
  collectData
  exit 0
fi

STARTUP_HOOK_FILE=".remoteX/custom/custom_pre_startup.sh"
if [ -f "$STARTUP_HOOK_FILE" ]; then
  chmod +x $STARTUP_HOOK_FILE && $STARTUP_HOOK_FILE
fi

## #1 add hermes build
if [ -f "$PROJECT_DIR/hermes.sh" ]; then
  echo "init build： hermes （because root dir has hermes.sh）"
  HERMES_START_TIME="$(date +%s)"
  chmod +x hermes.sh && ./hermes.sh -c -r $@
  HERMES_FINISH_TIME="$(date +%s)"
  echo "init hermes cost time： $((HERMES_FINISH_TIME - HERMES_START_TIME))"
fi

[ -d build ] || mkdir build
echo "$(date +%s)" >build/rx_start_time

# check branch status
CACHE_BRANCH=$(getCacheBranch)

# 生成本地配置
rLogger "generating local config..." true
TEMP_START_TIME="$(date +%s)"

/bin/bash .remoteX/code/local/remoteXClient.sh
if [ $? != 0 ]; then
  error_words="
  客户端同步失败，请先对照检查错误：
  1. 错误：JAVA_HOME is not set and no 'java' command could be found in your PATH; 解决：请自查 java home 是否设置并设置的路径是否有效，设置后再重试！
  2. 错误：local server execute failed; 解决：请先重试，如果不行执行 pkill java && rm -rf ~/.remoteX 完再重试！
  "
  saveError $PROJECT_DIR "$SAVED_USER_COMMAND" "$error_words" "" "客户端同步失败，请先按照提示解决！如果不能解决，可以 Oncall 协助解决！"
  throw ${syncClientExecException}
fi
rLogger "generate local config end!"

startSyncMonitor
startPreloadApk &

throwErrors
TIME_GENERATOR_CONFIG="$(($(date +%s) - TEMP_START_TIME))"

MACHINE_SERVER=$(readConfigProperty "machineServer")
K_RSYNC_PROXY=$(readConfigProperty "rsyncProxy")
RSYNC_SERVER=$(readConfigProperty "rsyncServer")
REMOTE_MACHINE_IP=$(readConfigProperty "hostIp")
WORKSPACE_ID=$(readConfigProperty "wsid")
USER_EMAIL=$(readConfigProperty "user")
MAIN_REPO_NAME=$(readConfigProperty "mainRepoName")
WS_ID=$(readConfigProperty "wsid")
REMOTE_DIR="/data00"
JAVA_TMP_DIR="/data00/tmpdir"

REPO_GIT_URL=$(readConfigProperty "repoUrl")
REPO_USER_EMAIL=$USER_EMAIL
USER_INPUT_COMMAND="$@"

if checkIfIncInstallRepo $REPO_GIT_URL; then
  collectModifiedFileInfo $PROJECT_DIR $USER_EMAIL $REPO_GIT_URL $@ &
fi

if [ -z "$REMOTE_MACHINE_IP" ]; then
  REMOTE_MACHINE_IP=$(execCmdToRemote "$REMOTE_DIR" 'echo \$REMOTEX_HOST_IP')
fi

MAIN_REPO_RELATIVE_PATH=$(mainRepoRelativePath)
ANDROID_REPO_NAME="$MAIN_REPO_NAME"
if [ -n "$MAIN_REPO_RELATIVE_PATH" ]; then
  ANDROID_REPO_NAME="$MAIN_REPO_NAME/$MAIN_REPO_RELATIVE_PATH"
fi

# 抛出 rsync proxy 环境
export RSYNC_PROXY=$K_RSYNC_PROXY

# 文件记录 main repo 一些信息，比如 rsync 优化结果等，主子进程通信
MAIN_REPO_DIFF_OPT=$(mktemp)

try
(
  if [[ -z "$USER_EMAIL" ]]; then
    echo "用户名不存在，请设置后重试，命令：git config --global user.name xxx 说明：xxx 为个人公司邮箱！"
    throw ${illegalUserException}
  fi
  ## check user input command and if hit to skip
  INPUT_ARGUS=$(echo "$@" | awk '{print tolower($0)}')
  DISPOSABLE_CMD=false
  if [[ "$INPUT_ARGUS" == kill* || "$INPUT_ARGUS" == killall* ]]; then
    echo "Custom Kill Not allowed, your command is: $@"
    echo "请使用 ./gradlew --stop"
    echo ""
    throw ${killNotAllowException}
  elif [[ $1 == "pull" ]]; then
    if [ $3 == "--batch" ]; then
      # ./start.sh pull -f --batch --dest=build/ a/a.apk b/b.apk c/c.apk ...
      # --batch: multiple files, --dest: one destination path [optional]
      # or pullBatchFiles -f tiger@10.11.12.13 /data00/xxx@bytedance.com/project/ /local_path --dest=build/ a/a.apk b/b.apk c/c.apk ...
      pullBatchFiles $2 $RSYNC_SERVER $ANDROID_REPO_NAME $PROJECT_DIR ${@:4}
    else
      # ./start.sh pull -f src dest
      pullFileOrDir $2 $3 $RSYNC_SERVER $ANDROID_REPO_NAME $PROJECT_DIR $4
    fi

    if [ $? -ne 0 ]; then
      echo "pull failure"
      echo ""
      throw ${pullFailureException}
    else
      echo "pull success"
      echo ""
      exit 0
    fi
  elif [[ $1 == "cleanBuildCache" ]]; then
    echo "start cleaning up gradle buildCache directories..."
    execCmdToRemote "$REMOTE_DIR" "rm -rf .gradle/caches/build-cache-1"
    execCmdToRemote "$REMOTE_DIR" "rm -rf .gradle/build-cache/*"
    echo "delete build cache done"

    execCmdToRemote "$REMOTE_DIR" "rm -rf .gradle/androidCache/*"
    echo "delete android cache done"
    echo ""
    DISPOSABLE_CMD=true
  elif [[ $1 == "clean" ]]; then
    echo "start cleaning workspace..."
    rm -rf build/${MAIN_REPO_NAME}_*
    execCmdToRemote "$REMOTE_DIR" "rm -rf *"
    echo "rm -rf done"
    echo ""
    DISPOSABLE_CMD=true
  elif [[ $1 == "cleanGradle" ]]; then
    echo "start cleaning gradle home..."
    execCmdToRemote "$REMOTE_DIR" "rm -rf .gradle/"
    echo "delete done!"
    DISPOSABLE_CMD=true
  elif [[ $1 == "deepClean" ]]; then
    echo "start deep cleaning workspace..."
    echo "cleaning cache dir..."
    execCmdToRemote "$REMOTE_DIR" "bash /remotex_env/disk_clean.sh"
    echo "clean cache dir done!"
    echo "cleaning workspace..."
    rm -rf build/${MAIN_REPO_NAME}_*
    execCmdToRemote "$REMOTE_DIR" "rm -rf *"
    echo "clean workspace done!"
    echo "deep clean done!"
    DISPOSABLE_CMD=true
  elif [[ $1 == "prune" ]]; then
    echo "start pruning..."
    PRUNE_CMD="find tmpdir -type f -amin +90 -delete; "
    PRUNE_CMD+="find .gradle/caches/transforms-2 .gradle/caches/transforms-3 .gradle/caches/modules-2 .gradle/caches/build-cache-1 .gradle/caches/build-cache .gradle/caches/build_galaxy_cache -type f -amin +180 -delete; "
    PRUNE_CMD+="find .gradle/caches -mindepth 1 -type d -empty -delete; "
    PRUNE_CMD+="find $ANDROID_REPO_NAME/.gradle/build-cache -type f -amin +180 -delete; "
    PRUNE_CMD+="echo 'cleanup cache done!'; "
    PRUNE_CMD+="echo 'stop daemon process!'; "
    PRUNE_CMD+="pkill -9 java; "
    PRUNE_CMD+="echo 'check the space occupied by workspace.'; "
    PRUNE_CMD+="df -h /data00"
    execCmdToRemote "$REMOTE_DIR" "$PRUNE_CMD"
    echo -e "\nprune done!"
    DISPOSABLE_CMD=true
  elif [[ $1 == "apkLink" ]]; then
    echo "uploading apk to tos..."
    execCmdToRemote "$REMOTE_DIR" "cd $ANDROID_REPO_NAME && bash $REMOTE_DIR/.remoteX/code/local/gen_apk_link.sh $ANDROID_REPO_NAME $USER_EMAIL"
    exit 0
  elif [[ $1 == pullCodeGen ]]; then
    pullCodeGen ${@:2}
  elif [[ $1 == "-r" ]]; then
    # 支持抖音多仓联编：https://bytedance.larkoffice.com/wiki/O7AKwzmxzilZl2kgAc0cl6znnnc
    repoName="$2"
    if [ -n "$repoName" ]; then
      repoName=$(getRepoName "${PROJECT_DIR}/build/repo_tag.txt" "$repoName")
      USER_INPUT_COMMAND="cd ../$repoName"
    fi
    otherParams=${@:3}
    if [ -n "$otherParams" ]; then
      USER_INPUT_COMMAND+=" && $otherParams"
    fi
  fi

  if [ $DISPOSABLE_CMD == true ]; then
    TAG=$(addTag "$TAG" "ws_operation=$1")
    collectData
    exit 0
  fi

  # rsync 同步配置文件至Server
  trimBeforeScript
  TEMP_START_TIME="$(date +%s)"
  # for test connection is ok
  rLogger "connect to remote server (和远端 server 建立连接)..." true
  testRsyncConnection "$RSYNC_SERVER" "$PROJECT_DIR/.remoteX/code/config.json"
  rLogger "connect to remote server done!"
  COMMAND=$(genRsyncLocalToRemoteCommand "$RSYNC_SERVER" "$PROJECT_DIR/.remoteX")
  COMMAND+=" --include='*/' "
  COMMAND+="--include='code/config.json' "
  COMMAND+="--include='code/local_dir.txt' "
  COMMAND+="--include='code/remote_revert_repo.py' "
  COMMAND+="--include='code/local/killGradleDaemon.sh' "
  COMMAND+="--include='code/local/env_set.sh' "
  COMMAND+="--include='code/local/upload_apk.sh' "
  COMMAND+="--include='code/local/gen_apk_link.sh' "
  COMMAND+="--include='custom/custom_before_exec.sh' "
  COMMAND+="--include='code/local/file_meta.sh' "
  COMMAND+="--include='code/local/remote_apk_patch.sh' "
  COMMAND+="--include='code/local/preload_apk_opt.sh' "
  if [ -f "$LOCAL_WORK_DIR/ws_phase.txt" ]; then
    COMMAND+="--include='code/ws_phase.txt' "
    WS_PHASE=$(cat "$LOCAL_WORK_DIR/ws_phase.txt")
    TAG=$(addTag "$TAG" "ws_phase=$WS_PHASE")
  fi
  COMMAND+="--exclude='*' "
  rLogger "sync local config  →  remote machine (同步本地配置文件到Server)..." true
  doRsync "$COMMAND" | tee -a "$(getRsyncLogFile)"
  rsync_code=${PIPESTATUS[0]}
  if [ $rsync_code != 0 ]; then
    if [ $rsync_code == 100 ]; then
      echo -e "\033[31m[error] found rsync Read-only file system error!\033[0m"
      collectRsyncError $rsync_code "Read-only file system"
      operateWorkspace "sleep"
      if checkWSStatus; then
        exec /bin/bash start.sh "selfUpdated" $@
      else
        throw ${rsyncException}
      fi
    else
      logColorInfo ""
      logColorError "Error: rsync 同步错误，错误码 $rsync_code"
      logColorInfo "Solution: 请执行命令尝试清除远端磁盘后重试，命令：./start.sh prune 或 lark 联系 wanghaoxun@bytedance.com 协助排查！"
      logColorInfo ""
      throw ${rsyncException}
    fi
  fi

  TIME_RSYNC_CONFIG="$(($(date +%s) - TEMP_START_TIME))"

  REPO_PREPARE_STATE_TIME="$(date +%s)"
  metaFileName=$(getMetaFileName)
  if [ ! -f "build/$metaFileName" ]; then
    collectMetaFileInfo &
    collectMetaBg=$!
  fi

  preloadApkInfo &>/dev/null &

  # 执行仓库还原 & custom config
  TEMP_START_TIME="$(date +%s)"
  COMMAND="python .remoteX/code/remote_revert_repo.py "
  if [[ $1 == "-d" ]]; then
    COMMAND+="True"
    USER_INPUT_COMMAND="${@:2}"
    eval set -- $USER_INPUT_COMMAND
  else
    COMMAND+="False"
  fi

  COMMAND+=" $(cloneValidDays)"
  COMMAND+=" $(readGlobalProperty 'remoteX.gitx.cleanup.enable' 'true')"
  gitLFSFetchInclude=$(readGlobalProperty 'remoteX.git.lfs.fetchinclude')
  if [ -n "$gitLFSFetchInclude" ]; then
    COMMAND+=" $gitLFSFetchInclude"
  fi

  gitLFSFetchExclude=$(readGlobalProperty 'remoteX.git.lfs.fetchexclude')
  if [ -n "$gitLFSFetchExclude" ]; then
    COMMAND+=" $gitLFSFetchExclude"
  fi

  echo ""
  echo "server clone code (server 还原代码)..."

  clone_log="build/clone_log"
  COMMAND="$COMMAND && if [ -f $MAIN_REPO_NAME/build/clone_flag ]; then echo -n 'clone_type='; cat $MAIN_REPO_NAME/build/clone_flag; fi"
  execCmdToRemote "$REMOTE_DIR" "$COMMAND" | tee $clone_log
  code=${PIPESTATUS[0]}
  if [ $code -ne 0 ]; then
    throw ${revertCodeException}
  fi
  TIME_REMOTE_CLONE="$(($(date +%s) - TEMP_START_TIME))"

  tail_log=$(cat $clone_log 2>/dev/null | tail -n 1)
  CLONE_TYPE=""
  if [[ "$tail_log" == clone_type=* ]]; then
    CLONE_TYPE=$(echo "$tail_log" | cut -d '=' -f2)
  fi

  if [ -n "$CLONE_TYPE" ] || shouldChangeFileMeta "$CACHE_BRANCH"; then
    rLogger "repo: $MAIN_REPO_NAME clone! clone_type=$CLONE_TYPE"
    # wait for all child processes to finish
    if [ -n "$collectMetaBg" ]; then
      rLogger "waiting for collect meta file info to finish"
      wait $collectMetaBg
    fi

    IS_INCREMENTAL="false"
    if [ -f "build/$metaFileName" ]; then
      TEMP_START_TIME="$(date +%s)"
      syncFileMeta "build/${metaFileName}"
      FILE_META_SYNC_TIME="$(($(date +%s) - TEMP_START_TIME))"

      logColorInfo ">>>>>> start to change remote file meta info. pls wait for a moment ... <<<<<<"
      rLogger "start to change remote file meta info"
      TEMP_START_TIME="$(date +%s)"
      metaChangeCmd="bash .remoteX/code/local/file_meta.sh $MAIN_REPO_NAME $REMOTE_DIR/logs/${metaFileName}"
      TAG=$(addTag "$TAG" "rsync_file_meta=true")
      metaChangedResult=false
      execCmdToRemote "$REMOTE_DIR" "$metaChangeCmd"
      if [ $? -eq 0 ]; then
        TAG=$(addTag "$TAG" "rsync_file_meta_result=true")
        metaChangedResult=true
      fi
      FILE_META_MODIFY_TIME="$(($(date +%s) - TEMP_START_TIME))"
      rLogger "change remote file meta info result: $metaChangedResult, cost: $FILE_META_MODIFY_TIME"
    fi

    if [ -f build/collect_meta_file_time ]; then
      FILE_META_COLLECT_TIME=$(cat build/collect_meta_file_time)
    fi
  fi

  REPO_PREPARE_COST_TIME="$(($(date +%s) - REPO_PREPARE_STATE_TIME))"

  if [ -f "$LOCAL_WORK_DIR/subRepos" ]; then
    for line in $(cat $LOCAL_WORK_DIR/subRepos); do
      repo_list+=($line)
    done
  fi

  if [ "${#repo_list[*]}" -gt 0 ]; then
    # 并发同步主仓 + 子仓./
    repo_list+=("main")
    syncRepoInParallel "${repo_list[@]}"
  else
    # 只同步主仓
    syncMainRepoByCache "${repo_list[@]}"
  fi

  if [ -f "$MAIN_REPO_DIFF_OPT" ]; then
    RSYNC_OPT_SUCCESSFUL=$(cat "$MAIN_REPO_DIFF_OPT")
    rLogger "sync finished! set RSYNC_OPT_SUCCESSFUL=$RSYNC_OPT_SUCCESSFUL"
    rm "$MAIN_REPO_DIFF_OPT"
  fi

  if [ -f build/sync_main_repo_time ]; then
    TIME_RSYNC_DIFF_MAIN=$(cat build/sync_main_repo_time)
  fi

  if [ "$TIME_RSYNC_DIFF_SUB_REPO" -gt 0 ]; then
    TIME_RSYNC_DIFF_SUB_REPO=$((TIME_RSYNC_DIFF_SUB_REPO - TIME_RSYNC_DIFF_MAIN))
  fi

  rLogger "all repo sync done! the config.json of $MAIN_REPO_NAME:"
  logFile=$(getRsyncLogFile)
  cat "$PROJECT_DIR/.remoteX/code/config.json" >>"$logFile"

  preloadLaunchInfo &>/dev/null &

  # 执行命令
  ## 用户自定义命令
  TEMP_START_TIME="$(date +%s)"
  REMOTE_COMMAND_SUCCESSFUL="false"
  # 是否需要拉apk包
  IS_PULL_APK="false"
  IS_PULL_AND_INSTALL_APK="false"

  ## 去除 -i 参数
  if [[ $1 == "-i" ]]; then
    IS_PULL_APK="true"
    USER_INPUT_COMMAND="${@:2}"
  fi

  # 去除 ci 参数
  if [[ $1 == "-ci" ]]; then
    IS_PULL_AND_INSTALL_APK="true"
    IS_PULL_APK="true"
    USER_INPUT_COMMAND="${@:2}"
  fi

  DEVICE_ID=$(getParamValue "--device" "$USER_INPUT_COMMAND")
  if [ -n "$DEVICE_ID" ]; then
    USER_INPUT_COMMAND=$(filterParam "--device" "$USER_INPUT_COMMAND")
  fi

  # Hook 用户输入命令
  ## hook stop参数，自己去stop
  if [[ "$USER_INPUT_COMMAND" == *./gradlew*--stop* ]]; then
    stopUserBuild
  fi

  if [[ ! -f "$LOCAL_WORK_DIR/not_use_gradle_progress" && "$IS_PULL_APK" == "false" ]]; then
    CONSOLE_RICH_ON=true
  fi
  DAEMON_MEMORY=$(readGlobalProperty 'remoteX.daemon.memory' '24g')
  KT_DAEMON_ENABLE=$(readGlobalProperty 'remoteX.kotlin.daemon.enable' 'true')

  # docker java cpu + IPv6 set
  JAVA_TOOL_OPTIONS="-XX:-UseContainerSupport"
  JAVA_TOOL_OPTIONS+=" -Djava.net.preferIPv6Addresses=true"

  COMMAND="source /etc/profile && export LANG=en_US.utf8 && export LC_CTYPE=en_US.utf8 && export JAVA_TOOL_OPTIONS='$JAVA_TOOL_OPTIONS' && chmod +x .remoteX/custom/custom_before_exec.sh && .remoteX/custom/custom_before_exec.sh $ANDROID_REPO_NAME "
  COMMAND+=" && chmod +x .remoteX/code/local/env_set.sh && .remoteX/code/local/env_set.sh $ANDROID_REPO_NAME $USER_EMAIL $REMOTE_DIR $JAVA_TMP_DIR $PROJECT_DIR $DAEMON_MEMORY $KT_DAEMON_ENABLE"
  COMMAND+=" && export GRADLE_USER_HOME=/data00/.gradle "
  if [ -n "$USER_INPUT_COMMAND" ]; then
    COMMAND+=" && cd $ANDROID_REPO_NAME && $USER_INPUT_COMMAND "
    chmod +x .remoteX/code/local/check_need_pull_apk.sh
    .remoteX/code/local/check_need_pull_apk.sh $MAIN_REPO_NAME $USER_INPUT_COMMAND
  fi

  COMMAND+=" && cd $REMOTE_DIR/$ANDROID_REPO_NAME && bash $REMOTE_DIR/.remoteX/code/local/upload_apk.sh $MAIN_REPO_NAME && source $REMOTE_DIR/.remoteX/code/local/preload_apk_opt.sh; uploadApkToServer"
  echo ""
  echo "start exec user command (开始执行用户命令): $@"

  trap handleTrap SIGINT SIGHUP SIGQUIT SIGTERM # EXIT
  pullPreloadApk

  # 设置用户执行是否成功
  ignoreErrors
  execCmdToRemote "$REMOTE_DIR" "mkdir -p $JAVA_TMP_DIR && $COMMAND"
  if [ $? == 0 ]; then
    REMOTE_COMMAND_SUCCESSFUL="true"
  fi

  getHummerBuildId "$ANDROID_REPO_NAME"
  # send to lark
  larkNoticeEnabled=$(readGlobalProperty 'lark.notice.enabled')
  if [[ "$larkNoticeEnabled" == "true" ]]; then
    sendLarkMsg $MAIN_REPO_NAME $USER_EMAIL $REMOTE_COMMAND_SUCCESSFUL
  fi

  throwErrors
  USER_INPUT_COMMAND=$@
  TIME_EXEC_USER_COMMAND="$(($(date +%s) - TEMP_START_TIME))"

  # rsync
  ## 回传数据 拉apk
  LOCAL_APK_PATH=""
  if [[ "$REMOTE_COMMAND_SUCCESSFUL" == "true" && $IS_PULL_APK == "true" ]]; then
    TEMP_START_TIME="$(date +%s)"
    if [ -f "$LOCAL_WORK_DIR_CUSTOM/apk_path.txt" ]; then
      LOCAL_APK_PATH=$(readCustomApkPath "$LOCAL_WORK_DIR_CUSTOM/apk_path.txt")
    fi

    if [ -z "$LOCAL_APK_PATH" ]; then
      ignoreErrors
      LOCAL_APK_PATH=$(pullAndReadApkDirFromFile)
      preloadLaunchInfo &>/dev/null &
      echo "Read gradle generated apk dir file, apk_dir_path: $LOCAL_APK_PATH"
    fi

    if [ -z "$LOCAL_APK_PATH" ]; then
      echo ""
      echo "search apk path...."
      APK_START_TIME="$(date +%s)"
      COMMAND="find $REMOTE_DIR/$ANDROID_REPO_NAME -name '*.apk' ! -name '*unsigned*.apk' -print0 | xargs -0 stat -c '%Y %n' | sort -rn | cut -d ' ' -f2 | grep build/outputs | head -1"
      APK_PATH=$(execCmdToRemote "$REMOTE_DIR/$ANDROID_REPO_NAME" "$COMMAND")

      FINISH_TIME="$(date +%s)"
      TIME_FIND_APK_PATH="$(($(date +%s) - TEMP_START_TIME))"
      echo "Search Apk Duration(耗时): $(formatTime $TIME_FIND_APK_PATH)"
      echo ""

      if [ -n "$APK_PATH" ]; then
        LOCAL_APK_PATH=$(convertLocalPath $APK_PATH "$REMOTE_DIR/$ANDROID_REPO_NAME/")
      fi
    fi

    if [ -n "$LOCAL_APK_PATH" ]; then
      AFTER=".apk"
      ## 判断是否是配置的目录
      if [[ $LOCAL_APK_PATH != *$AFTER* ]]; then
        LOCAL_APK_DIR=$LOCAL_APK_PATH
      else
        LOCAL_APK_DIR=$(dirname $LOCAL_APK_PATH)
      fi

      if [ ! -d "$PROJECT_DIR/$LOCAL_APK_DIR" ]; then
        mkdir -p $PROJECT_DIR/$LOCAL_APK_DIR
      fi

      ## #2 add hermes build
      if [ -f "$PROJECT_DIR/hermes.sh" ]; then
        chmod +x hermes.sh && $PROJECT_DIR/hermes.sh -c -r -a $REMOTE_COMMAND_SUCCESSFUL $@ &
      fi

      if [ "$IS_PULL_AND_INSTALL_APK" == true ] && ! isHermesEnabledAndWork; then
        # 在使用 -ci 时才尝试启用极速部署，生成 patch
        # 尝试使用云端 patch 方案
        makeAndPullApkPatch
        if [ $? -eq 0 ]; then
          APK_PATCH_GENERATED=true
        fi
        logColorInfo "apk patch generated: $APK_PATCH_GENERATED"
      fi

      if [ $APK_PATCH_GENERATED == false ]; then
        echo ""
        echo "try to pull remote apk to local..."
        # 本次rsync是否为增量rsync
        if [ $(find $PROJECT_DIR/$LOCAL_APK_DIR -name '*.apk' | tail -1) ]; then
          IS_INCREMENTAL_RSYNC=true
        else
          IS_INCREMENTAL_RSYNC=false
        fi

        # 是否有prefetch apk为本次rsync加速
        if [ -f "$(pwd)/build/apk/debug.apk" ]; then
          IS_USE_PREFETCH=true
        else
          IS_USE_PREFETCH=false
        fi
        copyApkToReal $PROJECT_DIR $REMOTE_DIR/$ANDROID_REPO_NAME $LOCAL_APK_PATH $MACHINE_SERVER $BUILD_TYPE
        replaceBuildApk "$LOCAL_APK_PATH"
        cancelAllPreloadTask
        pullApkWithHint
      fi
    else
      echo "apk path not found，rsync finish"
    fi
  fi

  # 执行用户自定义脚本
  ignoreErrors
  AFTER_EXEC_TIME="$(date +%s)"
  chmod +x .remoteX/custom/custom_after_exec.sh
  .remoteX/custom/custom_after_exec.sh $RSYNC_SERVER $ANDROID_REPO_NAME $REMOTE_COMMAND_SUCCESSFUL $@
  AFTER_EXEC_TIME="$(($(date +%s) - AFTER_EXEC_TIME))"

  # added only for plugin install
  if [ -f .remoteX/custom/custom_after_exec_apk.sh ]; then
    chmod +x .remoteX/custom/custom_after_exec_apk.sh
    .remoteX/custom/custom_after_exec_apk.sh $LOCAL_APK_PATH $RSYNC_SERVER $ANDROID_REPO_NAME $REMOTE_COMMAND_SUCCESSFUL $@
  fi

  if [[ "$REMOTE_COMMAND_SUCCESSFUL" == "true" && $IS_PULL_AND_INSTALL_APK == "true" ]]; then
    ignoreErrors
    INSTALL_APK_START_TIME="$(date +%s)"
    if [ $APK_PATCH_GENERATED == true ] && ! isHermesEnabledAndWork; then
      # 1.install patch
      packageName=$(getPackageName "$LOCAL_APK_PATH")
      # firstly, try to stop foreground app
      $(adbCommand) shell am force-stop "$packageName"
      installPatch "$packageName"
      INSTALL_APK_TIME="$(($(date +%s) - INSTALL_APK_START_TIME))"
      logColorInfo "apk patch install result: $APK_PATCH_OPT_RESULT"
      if [ $APK_PATCH_OPT_RESULT == true ]; then
        launchApk $LOCAL_APK_PATH $DEVICE_ID
        # 2.apk patch 成功：再拉 apk + 提示用户使用了 apk patch 方案 + 不统计耗时
        logColorWarn ""
        logColorWarn "apk patch 已经安装成功！请查看手机效果，但为了保证绝对正确，我们将把远端 apk 拉取回来!!!"
        logColorWarn "apk patch 已经安装成功！请查看手机效果，但为了保证绝对正确，我们将把远端 apk 拉取回来!!!"
        logColorWarn "apk patch 已经安装成功！请查看手机效果，但为了保证绝对正确，我们将把远端 apk 拉取回来!!!"
        logColorWarn ""
        pullApkWithHint false
        #showAPKPatchOptTips
      fi
    fi

    # 3.patch 失败了 or 没走 patch 方案
    if [ $APK_PATCH_OPT_RESULT != true ]; then
      # 4.使用了 patch 且失败，先拉 apk
      if [ $APK_PATCH_GENERATED == true ]; then
        pullApkWithHint
      fi

      if ! isHermesEnabledAndWork; then
        # 5.走 adb 安装
        INSTALL_APK_START_TIME="$(date +%s)"
        installAndLaunchApk $LOCAL_APK_PATH $DEVICE_ID
        if [ $? -ne 0 ]; then
          echo "======安装APK失败====="
          echo "1. 请确认APK路径是否正确"
          echo "2. 请确认ADB是否配置环境到变量"
          echo ""
        fi
        INSTALL_APK_TIME="$(($(date +%s) - INSTALL_APK_START_TIME))"
      fi
    fi
  fi

  # 编译失败拉错误文件至本地
  if [[ "$REMOTE_COMMAND_SUCCESSFUL" == "false" ]]; then
    mkdir -p build
    pullFileOrDir -f error_log.txt $RSYNC_SERVER $MAIN_REPO_NAME $PROJECT_DIR build/ >/dev/null 2>&1
    pullFileOrDir -f build/byte_build_scan.json $RSYNC_SERVER $MAIN_REPO_NAME $PROJECT_DIR build/ >/dev/null 2>&1
    if [ -f "$PROJECT_DIR/build/error_log.txt" ]; then
      ERROR_LOG=$(cat $PROJECT_DIR/build/error_log.txt)
      #    echo -e "\033[31m $ERROR_LOG \033[0m"
      echo "$ERROR_LOG"
    fi
  fi

  ignoreErrors
  BUILD_ID=$(cat build/hummer_build_id.txt)
  if [[ -n $BUILD_ID ]]; then
    echo ""
    echo "===================================================================================="
    if [ "$REMOTE_COMMAND_SUCCESSFUL" == "true" ]; then
      echo -e "\033[32mHummer Build Link:\033[0m https://hummer.bytedance.net?id=${BUILD_ID}&source=RemoteX"
    else
      echo -e "\033[31mHummer Build Link:\033[0m https://hummer.bytedance.net?id=${BUILD_ID}&source=RemoteX"
    fi
    echo "===================================================================================="
  fi

  FINISH_TIME="$(date +%s)"
  echo ""

  TIME_TOTAL="$((FINISH_TIME - START_TIME))"

  ## #3 add hermes build
  if [ -f "$PROJECT_DIR/hermes.sh" ]; then
    chmod +x hermes.sh && $PROJECT_DIR/hermes.sh -c -r -b $REMOTE_COMMAND_SUCCESSFUL $@
  fi

  if [ $RSYNC_OPT_SUCCESSFUL == true ] || [ $APK_PATCH_OPT_RESULT == true ]; then
    logColorInfo ""
    logColorInfo "本次命令使用了以下优化方案："
    if [ $RSYNC_OPT_SUCCESSFUL == true ]; then
      logColorInfo " - rsync 仓库上传优化，如果代码有异常，可以先查看远端文件是否和本地对齐，远端链接：https://remotex.bytedance.net"
      logColorInfo "  * 方案详见：https://bytedance.larkoffice.com/wiki/GCf7wyns2iO1l0kvFAycOOItnwf"
      logColorInfo "  * 优化开关命令，关闭：./start.sh closeRsyncOpt 开启：./start.sh openRsyncOpt"
      logColorInfo ""
    fi

    if [ $APK_PATCH_OPT_RESULT == true ]; then
      logColorInfo " - APK 极速部署方案，用于加速 APK 拉取和安装，如要安装完整 APK，可执行命令：./start.sh install"
      logColorInfo "  * 方案详见：https://bytedance.larkoffice.com/docx/R3H0dc8KToPLRkxJ8ARc0RfmnMh"
      logColorInfo "  * 优化开关命令，关闭：./start.sh closeApkOpt 开启：./start.sh openApkOpt"
    fi
    logColorInfo ""
  fi

  if [ "$REMOTE_COMMAND_SUCCESSFUL" == "true" ]; then
    echo "[32mSuccess with duration (编译总耗时): $(formatTime $TIME_TOTAL) [0m"
    echo ""
    collectData
    exit 0
  else
    echo "[31mFailure with duration (编译总耗时): $(formatTime $TIME_TOTAL) [0m"
    echo ""
    STACK_TRACE="编译代码失败, 请查看 hummer 错误链接解决！buildId: $BUILD_ID"
    collectData
    throw ${buildFailureException}
  fi
)
catch || {
  show_error=true
  collect_data=true
  case ${ex_code} in
  ${illegalUserException})
    STACK_TRACE="用户名不存在！ 请git config user.email 设置你字节邮箱后重试"
    ;;
  ${syncClientExecException})
    STACK_TRACE="sync client 执行失败"
    ;;
  ${killNotAllowException})
    STACK_TRACE="执行 kill 命令阻止，请使用命令 ./gradlew --stop"
    ;;
  ${pullFailureException})
    STACK_TRACE="拉取任意远端编译产物失败，可执行 ./start.sh cat xxx 来检查拉取文件/目录是否在远端存在！或者使用可视化前端 webshell 进去查看 https://remotex-workspace.bytedance.net 拉取产物的命令使用请查看：https://bytedance.feishu.cn/wiki/wikcn4sgLjSUYAEN89R4RDaEGUd"
    ;;
  ${revertCodeException})
    STACK_TRACE="远端服务器还原代码失败，请尝试 push 代码到远端再重试！"
    ;;
  ${rsyncException})
    STACK_TRACE="rsync 同步失败！"
    ;;
  ${buildFailureException})
    STACK_TRACE="编译代码失败, 请查看 hummer 错误链接解决！"
    show_error=false
    collect_data=false
    ;;
  esac
  # APK 编译异常
  APK_COMPILE_STATUS=0
  if [ "$collect_data" == true ]; then
    collectData
  fi

  if [ "$show_error" == true ]; then
    saveError $PROJECT_DIR "$SAVED_USER_COMMAND" "$STACK_TRACE" "" "请先按照提示解决问题， 如果不能解决，可以 Oncall 协助解决！"
  fi
  exit 1
}
