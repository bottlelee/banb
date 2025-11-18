#!/bin/bash
# handler_common.sh - 通用 handler 管理函数

# Handler 状态跟踪
declare -A HANDLER_TRIGGERED=()

# 触发 handler 执行
handler_trigger() {
    local handler_name="$1"
    local handler_file="$(dirname "${BASH_SOURCE[0]}")/${handler_name}.handler"
    
    if [[ ! -f "$handler_file" ]]; then
        echo "❌ Handler not found: $handler_name"
        return 1
    fi
    
    # 标记 handler 为已触发
    HANDLER_TRIGGERED["$handler_name"]=true
    
    echo "🔔 Triggering handler: $handler_name"
    
    # 执行 handler
    if [[ "${BANB_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $handler_file"
        return 0
    fi
    
    bash "$handler_file"
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        echo "✅ Handler executed successfully: $handler_name"
    else
        echo "❌ Handler execution failed: $handler_name"
    fi
    
    return $result
}

# 批量执行所有已触发的 handlers
handler_flush() {
    local handler_name
    
    if [[ "${BANB_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Would flush all triggered handlers"
        return 0
    fi
    
    for handler_name in "${!HANDLER_TRIGGERED[@]}"; do
        if [[ "${HANDLER_TRIGGERED[$handler_name]}" == "true" ]]; then
            handler_trigger "$handler_name"
        fi
    done
    
    # 清空触发状态
    HANDLER_TRIGGERED=()
}

# 检查 handler 是否已触发
handler_is_triggered() {
    local handler_name="$1"
    [[ "${HANDLER_TRIGGERED[$handler_name]:-false}" == "true" ]]
}

# 列出所有可用的 handlers
handler_list() {
    local handler_file
    
    echo "Available handlers:"
    for handler_file in "$(dirname "${BASH_SOURCE[0]}")"/*.handler; do
        if [[ -f "$handler_file" ]]; then
            local handler_name="$(basename "$handler_file" .handler)"
            local handler_desc=""
            
            # 提取 handler 描述
            if grep -q "# @description" "$handler_file"; then
                handler_desc=$(grep "# @description" "$handler_file" | head -1 | cut -d' ' -f3-)
            fi
            
            echo "  - $handler_name: $handler_desc"
        fi
    done
}