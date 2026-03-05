#!/bin/bash
# ============================================
# Sistema de Gerenciamento de Projetos
# Versão Standalone - Completa e Portável
# ============================================
#
# Instalação:
#   1. Copie este arquivo para ~/bin/projeto
#   2. chmod +x ~/bin/projeto
#   3. Adicione ao ~/.bashrc ou ~/.zshrc:
#      source ~/bin/projeto
#
# Uso rápido:
#   projeto criar --meu-app    # Criar projeto
#   projeto --meu-app          # Entrar no projeto
#   p meu-app                  # Atalho rápido
#   projeto help               # Ver ajuda
# ============================================

# ============================================
# CONFIGURAÇÃO
# ============================================

PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/projects}"
ACTIVE_DIR="$PROJECTS_ROOT/active"
ARCHIVED_DIR="$PROJECTS_ROOT/archived"
PERSONAL_DIR="$PROJECTS_ROOT/personal"

# Comprimento máximo de nome de projeto
_PROJETO_NOME_MAX=64

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# INICIALIZAÇÃO
# ============================================

_projeto_init() {
    # Criar estrutura de diretórios se não existir
    mkdir -p "$ACTIVE_DIR" "$PERSONAL_DIR" "$ARCHIVED_DIR"
}

# ============================================
# SANITIZAÇÃO DE NOMES
# ============================================

# Valida e sanitiza nome de projeto
# Retorna 0 se válido, 1 se inválido (com mensagem de erro)
_projeto_sanitizar_nome() {
    local nome="$1"

    if [ -z "$nome" ]; then
        echo -e "${RED}Erro: Nome do projeto não pode ser vazio${NC}"
        return 1
    fi

    # Bloquear path traversal
    if [[ "$nome" == *".."* ]] || [[ "$nome" == *"/"* ]]; then
        echo -e "${RED}Erro: Nome do projeto não pode conter '..' ou '/'${NC}"
        return 1
    fi

    # Bloquear nomes começando com . ou -
    if [[ "$nome" == .* ]] || [[ "$nome" == -* ]]; then
        echo -e "${RED}Erro: Nome do projeto não pode começar com '.' ou '-'${NC}"
        return 1
    fi

    # Limitar comprimento
    if [ ${#nome} -gt $_PROJETO_NOME_MAX ]; then
        echo -e "${RED}Erro: Nome do projeto não pode ter mais de $_PROJETO_NOME_MAX caracteres${NC}"
        return 1
    fi

    # Whitelist: apenas letras, números, ponto, underscore, hífen
    if [[ ! "$nome" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo -e "${RED}Erro: Nome do projeto contém caracteres inválidos${NC}"
        echo -e "${YELLOW}Permitido: letras, números, '.', '_', '-'${NC}"
        return 1
    fi

    return 0
}

# Verifica se um path é seguro (está dentro do PROJECTS_ROOT)
_projeto_verificar_path_seguro() {
    local path_to_check="$1"
    local base_dir="$2"

    if [ -z "$path_to_check" ] || [ -z "$base_dir" ]; then
        return 1
    fi

    local path_real
    path_real=$(realpath -m "$path_to_check" 2>/dev/null) || return 1
    local base_real
    base_real=$(realpath -m "$base_dir" 2>/dev/null) || return 1

    [[ "$path_real" == "$base_real"* ]]
}

# ============================================
# CARREGAMENTO SEGURO DE CONFIGURAÇÃO
# ============================================

# Valida .projeto-env antes de fazer source
# Rejeita se contém padrões perigosos
_projeto_validar_env_file() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 1
    fi

    # Padrões perigosos que não devem estar em .projeto-env
    local patterns_perigosos=(
        'eval '
        'exec '
        '\brm\b.*-rf'
        '\bdd\b '
        'mkfs\.'
        '> /dev/'
        'chmod.*777'
        'curl.*|.*sh'
        'wget.*|.*sh'
        '\bsudo\b'
        '\bsu\b '
    )

    for pattern in "${patterns_perigosos[@]}"; do
        if grep -qE "$pattern" "$file" 2>/dev/null; then
            return 1
        fi
    done

    return 0
}

# Carrega .projeto-config de forma segura (sem source)
# Lê apenas variáveis conhecidas com regex
_projeto_carregar_config() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 1
    fi

    # Ler apenas variáveis específicas e conhecidas
    local val
    val=$(grep -E '^PROJETO_NOME=' "$file" 2>/dev/null | head -1 | sed 's/^PROJETO_NOME=//;s/^"//;s/"$//')
    [ -n "$val" ] && PROJETO_NOME="$val"

    val=$(grep -E '^PROJETO_TIPO=' "$file" 2>/dev/null | head -1 | sed 's/^PROJETO_TIPO=//;s/^"//;s/"$//')
    [ -n "$val" ] && PROJETO_TIPO="$val"

    val=$(grep -E '^PROJETO_CRIADO=' "$file" 2>/dev/null | head -1 | sed 's/^PROJETO_CRIADO=//;s/^"//;s/"$//')
    [ -n "$val" ] && PROJETO_CRIADO="$val"

    val=$(grep -E '^PROJETO_LINGUAGEM=' "$file" 2>/dev/null | head -1 | sed 's/^PROJETO_LINGUAGEM=//;s/^"//;s/"$//')
    [ -n "$val" ] && PROJETO_LINGUAGEM="$val"

    val=$(grep -E '^PROJETO_IMPORTADO=' "$file" 2>/dev/null | head -1 | sed 's/^PROJETO_IMPORTADO=//;s/^"//;s/"$//')
    [ -n "$val" ] && PROJETO_IMPORTADO="$val"

    val=$(grep -E '^PROJETO_REPO=' "$file" 2>/dev/null | head -1 | sed 's/^PROJETO_REPO=//;s/^"//;s/"$//')
    [ -n "$val" ] && PROJETO_REPO="$val"

    return 0
}

# ============================================
# PROJETO JAIL - RESTRIÇÃO DE NAVEGAÇÃO
# ============================================

# Verificação central: o path está dentro do projeto?
_projeto_path_dentro_do_projeto() {
    local path_check="$1"
    local projeto_real
    projeto_real=$(realpath -m "$PROJETO_ATUAL_PATH" 2>/dev/null) || return 1

    local check_real
    check_real=$(realpath -m "$path_check" 2>/dev/null) || return 1

    # Deve ser exatamente o projeto ou subpath dele (com /)
    [[ "$check_real" == "$projeto_real" || "$check_real" == "$projeto_real/"* ]]
}

# Override do comando cd para restringir navegação (usando função, não alias)
_projeto_cd_jail() {
    # Se não estiver em um projeto, cd normal
    if [ -z "$PROJETO_ATUAL_PATH" ]; then
        builtin cd "$@"
        return $?
    fi

    local target="$1"

    # Resolver caminho absoluto do destino
    local destino
    if [ -z "$target" ]; then
        # cd sem argumentos tenta ir para HOME - bloquear
        echo -e "${RED}✗ Você está dentro do projeto '$PROJETO_ATUAL'${NC}"
        echo -e "${YELLOW}Use 'projeto sair' para sair do projeto${NC}"
        return 1
    elif [ "$target" = "-" ]; then
        # cd - usa OLDPWD - verificar se está dentro do projeto
        destino="$OLDPWD"
    else
        # Resolver caminho relativo
        destino=$(builtin cd -P -- "$target" 2>/dev/null && pwd) || destino="$target"
    fi

    if _projeto_path_dentro_do_projeto "$destino"; then
        builtin cd "$@"
        return $?
    else
        echo -e "${RED}✗ Não é possível navegar para fora do projeto '$PROJETO_ATUAL'${NC}"
        echo -e "${YELLOW}Caminho bloqueado: $target${NC}"
        echo -e "${YELLOW}Use 'projeto sair' para sair do projeto${NC}"
        return 1
    fi
}

# Override de pushd para jail
_projeto_pushd_jail() {
    if [ -z "$PROJETO_ATUAL_PATH" ]; then
        builtin pushd "$@"
        return $?
    fi

    local target="$1"
    local destino
    if [ -z "$target" ]; then
        builtin pushd
        return $?
    fi
    destino=$(builtin cd -P -- "$target" 2>/dev/null && pwd) || destino="$target"

    if _projeto_path_dentro_do_projeto "$destino"; then
        builtin pushd "$@"
        return $?
    else
        echo -e "${RED}✗ pushd bloqueado: fora do projeto '$PROJETO_ATUAL'${NC}"
        echo -e "${YELLOW}Use 'projeto sair' para sair do projeto${NC}"
        return 1
    fi
}

# Override de popd para jail
_projeto_popd_jail() {
    if [ -z "$PROJETO_ATUAL_PATH" ]; then
        builtin popd "$@"
        return $?
    fi

    # Simular popd para verificar destino
    local destino
    destino=$(builtin popd -n "$@" 2>/dev/null && pwd) || destino=""

    if [ -z "$destino" ] || _projeto_path_dentro_do_projeto "$destino"; then
        builtin popd "$@"
        return $?
    else
        echo -e "${RED}✗ popd bloqueado: destino fora do projeto '$PROJETO_ATUAL'${NC}"
        return 1
    fi
}

# Override de exec para bloquear novas shells dentro do jail
_projeto_exec_jail() {
    if [ -z "$PROJETO_ATUAL_PATH" ]; then
        builtin exec "$@"
        return $?
    fi

    # Bloquear exec de shells que eliminariam o jail
    local cmd="$1"
    local cmd_base
    cmd_base=$(basename "$cmd" 2>/dev/null)
    case "$cmd_base" in
        bash|sh|zsh|dash|ksh|fish|csh|tcsh)
            echo -e "${RED}✗ exec de shell bloqueado dentro do jail${NC}"
            echo -e "${YELLOW}Use 'projeto sair' para sair do projeto${NC}"
            return 1
            ;;
        *)
            builtin exec "$@"
            ;;
    esac
}

# Wrappers de proteção de acesso a arquivos fora do projeto
_projeto_verificar_args_path() {
    # Verifica se algum argumento de path está fora do projeto
    # Retorna 0 se todos ok, 1 se algum está fora
    local projeto_real
    projeto_real=$(realpath -m "$PROJETO_ATUAL_PATH" 2>/dev/null) || return 1

    for arg in "$@"; do
        # Ignorar flags (começam com -)
        [[ "$arg" == -* ]] && continue
        # Ignorar argumentos vazios
        [ -z "$arg" ] && continue

        # Resolver path (relativo ao PWD)
        local arg_real
        if [[ "$arg" == /* ]]; then
            arg_real=$(realpath -m "$arg" 2>/dev/null) || continue
        else
            arg_real=$(realpath -m "$PWD/$arg" 2>/dev/null) || continue
        fi

        if [[ "$arg_real" != "$projeto_real" && "$arg_real" != "$projeto_real/"* ]]; then
            echo -e "${RED}✗ Acesso bloqueado: $arg (fora do projeto)${NC}"
            return 1
        fi
    done
    return 0
}

# Wrapper genérico para comandos de arquivo
_projeto_file_cmd_wrapper() {
    local real_cmd="$1"
    shift

    if [ -z "$PROJETO_ATUAL_PATH" ]; then
        command "$real_cmd" "$@"
        return $?
    fi

    if _projeto_verificar_args_path "$@"; then
        command "$real_cmd" "$@"
        return $?
    else
        echo -e "${YELLOW}Use 'projeto sair' para acessar arquivos fora do projeto${NC}"
        return 1
    fi
}

# Wrapper específico para ln que bloqueia symlinks para fora
_projeto_ln_jail() {
    if [ -z "$PROJETO_ATUAL_PATH" ]; then
        command ln "$@"
        return $?
    fi

    # Verificar paths de destino e também targets de symlinks
    local args=("$@")
    local has_s=0
    for arg in "${args[@]}"; do
        [[ "$arg" == *s* && "$arg" == -* ]] && has_s=1
    done

    if [ $has_s -eq 1 ]; then
        # Para symlinks, verificar que o target está dentro do projeto
        local target=""
        local skip_next=0
        for arg in "${args[@]}"; do
            if [ $skip_next -eq 1 ]; then
                skip_next=0
                continue
            fi
            [[ "$arg" == -* ]] && continue
            if [ -z "$target" ]; then
                target="$arg"
            fi
        done

        if [ -n "$target" ]; then
            local target_real
            if [[ "$target" == /* ]]; then
                target_real=$(realpath -m "$target" 2>/dev/null)
            else
                target_real=$(realpath -m "$PWD/$target" 2>/dev/null)
            fi

            local projeto_real
            projeto_real=$(realpath -m "$PROJETO_ATUAL_PATH" 2>/dev/null)

            if [[ "$target_real" != "$projeto_real" && "$target_real" != "$projeto_real/"* ]]; then
                echo -e "${RED}✗ Symlink bloqueado: target '$target' está fora do projeto${NC}"
                return 1
            fi
        fi
    fi

    if _projeto_verificar_args_path "$@"; then
        command ln "$@"
        return $?
    else
        echo -e "${YELLOW}Use 'projeto sair' para acessar arquivos fora do projeto${NC}"
        return 1
    fi
}

# Trap DEBUG: verifica $PWD após cada comando e força volta se escapou
_projeto_debug_trap() {
    if [ -n "$PROJETO_ATUAL_PATH" ] && [ -n "$PROJETO_JAIL_ATIVO" ]; then
        if ! _projeto_path_dentro_do_projeto "$PWD"; then
            echo -e "${RED}✗ Detectada saída do projeto. Retornando...${NC}"
            builtin cd "$PROJETO_ATUAL_PATH"
        fi
    fi
}

# Lista de comandos que recebem wrappers no jail
_PROJETO_JAIL_CMDS=(cat less more head tail vim nano vi cp mv ln rm)

# Ativar/desativar jail
_projeto_ativar_jail() {
    # Bloquear CDPATH
    export CDPATH=""

    if [ -n "$BASH_VERSION" ]; then
        # Bash: usar funções (não aliases, que são bypassáveis com \cmd)
        cd() { _projeto_cd_jail "$@"; }
        pushd() { _projeto_pushd_jail "$@"; }
        popd() { _projeto_popd_jail "$@"; }
        exec() { _projeto_exec_jail "$@"; }

        # Wrappers de acesso a arquivos
        cat() { _projeto_file_cmd_wrapper cat "$@"; }
        less() { _projeto_file_cmd_wrapper less "$@"; }
        more() { _projeto_file_cmd_wrapper more "$@"; }
        head() { _projeto_file_cmd_wrapper head "$@"; }
        tail() { _projeto_file_cmd_wrapper tail "$@"; }
        vim() { _projeto_file_cmd_wrapper vim "$@"; }
        nano() { _projeto_file_cmd_wrapper nano "$@"; }
        vi() { _projeto_file_cmd_wrapper vi "$@"; }
        cp() { _projeto_file_cmd_wrapper cp "$@"; }
        mv() { _projeto_file_cmd_wrapper mv "$@"; }
        ln() { _projeto_ln_jail "$@"; }

        # Ativar trap DEBUG para detectar escapes via subshell/command cd/builtin cd
        trap '_projeto_debug_trap' DEBUG

    elif [ -n "$ZSH_VERSION" ]; then
        cd() { _projeto_cd_jail "$@"; }
        pushd() { _projeto_pushd_jail "$@"; }
        popd() { _projeto_popd_jail "$@"; }
        exec() { _projeto_exec_jail "$@"; }
        cat() { _projeto_file_cmd_wrapper cat "$@"; }
        less() { _projeto_file_cmd_wrapper less "$@"; }
        more() { _projeto_file_cmd_wrapper more "$@"; }
        head() { _projeto_file_cmd_wrapper head "$@"; }
        tail() { _projeto_file_cmd_wrapper tail "$@"; }
        vim() { _projeto_file_cmd_wrapper vim "$@"; }
        nano() { _projeto_file_cmd_wrapper nano "$@"; }
        vi() { _projeto_file_cmd_wrapper vi "$@"; }
        cp() { _projeto_file_cmd_wrapper cp "$@"; }
        mv() { _projeto_file_cmd_wrapper mv "$@"; }
        ln() { _projeto_ln_jail "$@"; }
    fi

    export PROJETO_JAIL_ATIVO="1"
}

_projeto_desativar_jail() {
    if [ -n "$BASH_VERSION" ]; then
        # Remover trap DEBUG
        trap - DEBUG

        # Remover funções que sobrescrevem builtins/comandos
        unset -f cd 2>/dev/null
        unset -f pushd 2>/dev/null
        unset -f popd 2>/dev/null
        unset -f exec 2>/dev/null
        unset -f cat 2>/dev/null
        unset -f less 2>/dev/null
        unset -f more 2>/dev/null
        unset -f head 2>/dev/null
        unset -f tail 2>/dev/null
        unset -f vim 2>/dev/null
        unset -f nano 2>/dev/null
        unset -f vi 2>/dev/null
        unset -f cp 2>/dev/null
        unset -f mv 2>/dev/null
        unset -f ln 2>/dev/null

    elif [ -n "$ZSH_VERSION" ]; then
        unfunction cd 2>/dev/null
        unfunction pushd 2>/dev/null
        unfunction popd 2>/dev/null
        unfunction exec 2>/dev/null
        unfunction cat 2>/dev/null
        unfunction less 2>/dev/null
        unfunction more 2>/dev/null
        unfunction head 2>/dev/null
        unfunction tail 2>/dev/null
        unfunction vim 2>/dev/null
        unfunction nano 2>/dev/null
        unfunction vi 2>/dev/null
        unfunction cp 2>/dev/null
        unfunction mv 2>/dev/null
        unfunction ln 2>/dev/null
    fi

    unset PROJETO_JAIL_ATIVO
    # Restaurar CDPATH
    unset CDPATH
}

# ============================================
# PERFIL ISOLADO POR PROJETO
# ============================================

_projeto_ativar_git_identity() {
    local projeto_dir="$1"
    local config_file="$projeto_dir/.projeto-config"

    [ -f "$config_file" ] || return 0

    local git_name git_email
    git_name=$(grep -E '^PROJETO_GIT_NAME=' "$config_file" | head -1 | sed 's/^PROJETO_GIT_NAME=//;s/^"//;s/"$//')
    git_email=$(grep -E '^PROJETO_GIT_EMAIL=' "$config_file" | head -1 | sed 's/^PROJETO_GIT_EMAIL=//;s/^"//;s/"$//')

    [ -n "$git_name" ] && export GIT_AUTHOR_NAME="$git_name" && export GIT_COMMITTER_NAME="$git_name"
    [ -n "$git_email" ] && export GIT_AUTHOR_EMAIL="$git_email" && export GIT_COMMITTER_EMAIL="$git_email"
}

_projeto_ativar_perfil() {
    local projeto_dir="$PROJETO_ATUAL_PATH"
    local nome="$PROJETO_ATUAL"

    # Salvar estado original para restauração
    export _PROJETO_ORIG_PS1="$PS1"
    export _PROJETO_ORIG_HOME="$HOME"
    export _PROJETO_ORIG_HISTFILE="$HISTFILE"
    export _PROJETO_ORIG_PATH="$PATH"
    export _PROJETO_ORIG_TMPDIR="${TMPDIR:-}"
    export _PROJETO_ORIG_XDG_CACHE_HOME="${XDG_CACHE_HOME:-}"
    export _PROJETO_ORIG_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-}"
    export _PROJETO_ORIG_XDG_DATA_HOME="${XDG_DATA_HOME:-}"

    # PS1 customizado
    export PS1="\[\033[0;36m\]projeto\[\033[0m\]@\[\033[0;32m\]${nome}\[\033[0m\] \W \$ "

    # HISTFILE isolado
    export HISTFILE="$projeto_dir/.projeto-history"
    touch "$HISTFILE"
    history -r "$HISTFILE" 2>/dev/null

    # HOME temporário
    export HOME="$projeto_dir"

    # PATH com bin local do projeto
    mkdir -p "$projeto_dir/bin"
    export PATH="$projeto_dir/bin:$projeto_dir/node_modules/.bin:$PATH"

    # XDG dirs isolados
    mkdir -p "$projeto_dir/.local/cache" "$projeto_dir/.local/config" "$projeto_dir/.local/data"
    export XDG_CACHE_HOME="$projeto_dir/.local/cache"
    export XDG_CONFIG_HOME="$projeto_dir/.local/config"
    export XDG_DATA_HOME="$projeto_dir/.local/data"

    # TMPDIR isolado
    mkdir -p "$projeto_dir/.tmp"
    export TMPDIR="$projeto_dir/.tmp"

    # Git identity per-project (se configurado)
    _projeto_ativar_git_identity "$projeto_dir"

    # Carregar aliases/env extras do projeto
    [ -f "$projeto_dir/.projeto-aliases" ] && source "$projeto_dir/.projeto-aliases" 2>/dev/null
}

_projeto_desativar_perfil() {
    # Salvar history do projeto antes de sair
    [ -n "$HISTFILE" ] && history -w "$HISTFILE" 2>/dev/null

    # Restaurar estado original
    export PS1="$_PROJETO_ORIG_PS1"
    export HOME="$_PROJETO_ORIG_HOME"
    export HISTFILE="$_PROJETO_ORIG_HISTFILE"
    export PATH="$_PROJETO_ORIG_PATH"

    if [ -n "$_PROJETO_ORIG_TMPDIR" ]; then
        export TMPDIR="$_PROJETO_ORIG_TMPDIR"
    else
        unset TMPDIR
    fi

    # Restaurar XDG
    if [ -n "$_PROJETO_ORIG_XDG_CACHE_HOME" ]; then
        export XDG_CACHE_HOME="$_PROJETO_ORIG_XDG_CACHE_HOME"
    else
        unset XDG_CACHE_HOME
    fi
    if [ -n "$_PROJETO_ORIG_XDG_CONFIG_HOME" ]; then
        export XDG_CONFIG_HOME="$_PROJETO_ORIG_XDG_CONFIG_HOME"
    else
        unset XDG_CONFIG_HOME
    fi
    if [ -n "$_PROJETO_ORIG_XDG_DATA_HOME" ]; then
        export XDG_DATA_HOME="$_PROJETO_ORIG_XDG_DATA_HOME"
    else
        unset XDG_DATA_HOME
    fi

    # Carregar history original
    [ -n "$HISTFILE" ] && history -r "$HISTFILE" 2>/dev/null

    # Remover git identity do projeto
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

    # Limpar variáveis de backup
    unset _PROJETO_ORIG_PS1 _PROJETO_ORIG_HOME _PROJETO_ORIG_HISTFILE
    unset _PROJETO_ORIG_PATH _PROJETO_ORIG_TMPDIR
    unset _PROJETO_ORIG_XDG_CACHE_HOME _PROJETO_ORIG_XDG_CONFIG_HOME _PROJETO_ORIG_XDG_DATA_HOME
}

_projeto_perfil() {
    local projeto_dir="$PROJETO_ATUAL_PATH"
    if [ -z "$projeto_dir" ]; then
        echo -e "${RED}Erro: entre em um projeto primeiro${NC}"
        return 1
    fi

    local config_file="$projeto_dir/.projeto-config"

    echo -e "${BLUE}Configurar perfil do projeto: $PROJETO_ATUAL${NC}"
    echo ""

    # Ler valores atuais
    local current_name="" current_email=""
    if [ -f "$config_file" ]; then
        current_name=$(grep -E '^PROJETO_GIT_NAME=' "$config_file" | head -1 | sed 's/^PROJETO_GIT_NAME=//;s/^"//;s/"$//')
        current_email=$(grep -E '^PROJETO_GIT_EMAIL=' "$config_file" | head -1 | sed 's/^PROJETO_GIT_EMAIL=//;s/^"//;s/"$//')
    fi

    read -p "Git user.name [${current_name:-não configurado}]: " git_name
    read -p "Git user.email [${current_email:-não configurado}]: " git_email

    # Usar valor atual se vazio
    git_name="${git_name:-$current_name}"
    git_email="${git_email:-$current_email}"

    # Atualizar config file
    if [ -f "$config_file" ]; then
        # Remover linhas existentes de git
        local tmp_file="$config_file.tmp"
        grep -v -E '^PROJETO_GIT_(NAME|EMAIL)=' "$config_file" > "$tmp_file" 2>/dev/null || true
        mv "$tmp_file" "$config_file"
    fi

    # Adicionar novas linhas
    [ -n "$git_name" ] && echo "PROJETO_GIT_NAME=\"$git_name\"" >> "$config_file"
    [ -n "$git_email" ] && echo "PROJETO_GIT_EMAIL=\"$git_email\"" >> "$config_file"

    # Aplicar imediatamente
    [ -n "$git_name" ] && export GIT_AUTHOR_NAME="$git_name" && export GIT_COMMITTER_NAME="$git_name"
    [ -n "$git_email" ] && export GIT_AUTHOR_EMAIL="$git_email" && export GIT_COMMITTER_EMAIL="$git_email"

    echo ""
    echo -e "${GREEN}Perfil atualizado!${NC}"
    [ -n "$git_name" ] && echo -e "  Git name:  ${CYAN}$git_name${NC}"
    [ -n "$git_email" ] && echo -e "  Git email: ${CYAN}$git_email${NC}"
}

# ============================================
# FUNÇÃO PRINCIPAL
# ============================================

projeto() {
    _projeto_init

    local comando="$1"
    local nome=""

    # Parse argumentos
    if [[ "$comando" == --* ]]; then
        # projeto --nome (entrar no projeto)
        nome="${comando#--}"
        comando="entrar"
    elif [[ "$2" == --* ]]; then
        # projeto criar --nome
        nome="${2#--}"
    else
        # projeto help ou outros
        nome="$2"
    fi

    case "$comando" in
        criar)
            _projeto_criar "$nome"
            ;;
        importar|import)
            _projeto_importar "$nome"
            ;;
        entrar|--*)
            _projeto_entrar "$nome"
            ;;
        sair|exit|quit)
            _projeto_sair
            ;;
        listar|ls|list)
            _projeto_listar "$nome"
            ;;
        mover|mv|move)
            _projeto_mover "$nome" "$3"
            ;;
        arquivar|archive)
            _projeto_arquivar "$nome"
            ;;
        remover|rm|delete)
            _projeto_remover "$nome"
            ;;
        info)
            _projeto_info "$nome"
            ;;
        perfil|profile)
            _projeto_perfil
            ;;
        help|ajuda|--help|-h|"")
            _projeto_help
            ;;
        *)
            echo -e "${RED}Comando desconhecido: $comando${NC}"
            _projeto_help
            return 1
            ;;
    esac
}

# ============================================
# CRIAR PROJETO
# ============================================

_projeto_criar() {
    local nome="$1"
    local tipo="${2:-active}"

    if [ -z "$nome" ]; then
        echo -e "${RED}Erro: Nome do projeto não especificado${NC}"
        echo "Uso: projeto criar --nome-do-projeto [tipo]"
        return 1
    fi

    # Validar nome do projeto
    if ! _projeto_sanitizar_nome "$nome"; then
        return 1
    fi

    # Perguntar tipo se não especificado
    if [ -z "$2" ]; then
        echo -e "${BLUE}Onde criar o projeto?${NC}"
        echo "1) active (padrão)"
        echo "2) personal"
        echo "3) archived"
        read -p "Escolha [1]: " escolha

        case "${escolha:-1}" in
            1) tipo="active" ;;
            2) tipo="personal" ;;
            3) tipo="archived" ;;
            *) tipo="active" ;;
        esac
    fi

    local projeto_dir="$PROJECTS_ROOT/$tipo/$nome"

    if [ -d "$projeto_dir" ]; then
        echo -e "${YELLOW}Projeto já existe: $projeto_dir${NC}"
        return 1
    fi

    echo -e "${GREEN}Criando projeto: $nome em $tipo/${NC}"

    # Criar estrutura
    mkdir -p "$projeto_dir"/{src,docs,tests,config}

    # Criar README
    cat > "$projeto_dir/README.md" <<EOF
# $nome

Projeto criado em: $(date +"%Y-%m-%d %H:%M:%S")
Status: $tipo

## Descrição

[Adicione descrição do projeto aqui]

## Estrutura

- \`src/\` - Código fonte
- \`docs/\` - Documentação
- \`tests/\` - Testes
- \`config/\` - Configurações

## Setup

[Instruções de instalação]

## Uso

[Instruções de uso]
EOF

    # Criar .gitignore básico
    cat > "$projeto_dir/.gitignore" <<EOF
# Ambientes virtuais
venv/
env/
.venv/
node_modules/

# IDEs
.vscode/
.idea/
*.swp
*.swo

# Sistema
.DS_Store
Thumbs.db

# Logs e temporários
*.log
.env
.env.local
*.tmp

# Build
dist/
build/
*.egg-info/
__pycache__/
*.pyc

# Perfil do projeto
.projeto-history
.tmp/
.local/
EOF

    # Criar configuração do projeto
    cat > "$projeto_dir/.projeto-config" <<EOF
# Configuração do Projeto
PROJETO_NOME="$nome"
PROJETO_TIPO="$tipo"
PROJETO_CRIADO="$(date +"%Y-%m-%d %H:%M:%S")"
PROJETO_LINGUAGEM=""
PROJETO_VENV=""

# Git identity (configurar com: projeto perfil)
PROJETO_GIT_NAME=""
PROJETO_GIT_EMAIL=""
EOF

    # Criar script de ambiente
    cat > "$projeto_dir/.projeto-env" <<'ENVEOF'
#!/bin/bash
# Ambiente do projeto
# Este arquivo é source-ado ao entrar no projeto

# Variáveis de ambiente
export PROJETO_NOME="NOME_PLACEHOLDER"
export PROJETO_ROOT="DIR_PLACEHOLDER"

# Adicione suas variáveis de ambiente aqui
# export DATABASE_URL="..."
# export API_KEY="..."

# Ativar ambiente virtual se existir
if [ -d "$PROJETO_ROOT/venv" ]; then
    source "$PROJETO_ROOT/venv/bin/activate"
fi

# Aliases específicos do projeto
# alias test="python -m pytest"
# alias run="npm start"

echo -e "\033[0;32mAmbiente do projeto NOME_PLACEHOLDER ativado\033[0m"
ENVEOF

    # Substituir placeholders (nome já sanitizado, seguro para sed)
    sed -i "s@NOME_PLACEHOLDER@${nome}@g" "$projeto_dir/.projeto-env"
    sed -i "s@DIR_PLACEHOLDER@${projeto_dir}@g" "$projeto_dir/.projeto-env"
    chmod +x "$projeto_dir/.projeto-env"

    # Inicializar git
    if command -v git &> /dev/null; then
        (cd "$projeto_dir" && git init -q && git add . && git commit -q -m "Initial commit: projeto $nome")
        echo -e "${GREEN}Repositório git inicializado${NC}"
    fi

    echo -e "${GREEN}✓ Projeto '$nome' criado com sucesso!${NC}"
    echo -e "${BLUE}Entre no projeto com: projeto --$nome${NC}"

    # Perguntar se quer entrar
    read -p "Entrar no projeto agora? [S/n]: " entrar
    if [[ "${entrar:-s}" =~ ^[Ss]$ ]]; then
        _projeto_entrar "$nome"
    fi
}

# ============================================
# ENTRAR NO PROJETO
# ============================================

_projeto_entrar() {
    # Ativar arrays baseados em 0 para compatibilidade bash/zsh
    [ -n "$ZSH_VERSION" ] && setopt local_options KSH_ARRAYS

    local nome="$1"

    if [ -z "$nome" ]; then
        echo -e "${RED}Erro: Nome do projeto não especificado${NC}"
        echo "Uso: projeto --nome-do-projeto"
        return 1
    fi

    # Bloquear path traversal na busca
    if [[ "$nome" == *".."* ]] || [[ "$nome" == *"/"* ]]; then
        echo -e "${RED}Erro: Nome de projeto inválido${NC}"
        return 1
    fi

    # Procurar projeto
    local projeto_dir=""
    local nome_encontrado=""

    # Tentar match exato primeiro
    if [ -d "$ACTIVE_DIR/$nome" ]; then
        projeto_dir="$ACTIVE_DIR/$nome"
        nome_encontrado="$nome"
    elif [ -d "$PERSONAL_DIR/$nome" ]; then
        projeto_dir="$PERSONAL_DIR/$nome"
        nome_encontrado="$nome"
    elif [ -d "$ARCHIVED_DIR/$nome" ]; then
        projeto_dir="$ARCHIVED_DIR/$nome"
        nome_encontrado="$nome"
        echo -e "${YELLOW}Aviso: Este projeto está arquivado${NC}"
    else
        # Não encontrou exato, fazer fuzzy search
        local encontrados=()
        local encontrados_paths=()

        # Buscar em todos os diretórios
        if [ -n "$BASH_VERSION" ]; then
            shopt -s nullglob
        elif [ -n "$ZSH_VERSION" ]; then
            setopt local_options nullglob
        fi

        for dir in "$ACTIVE_DIR" "$PERSONAL_DIR" "$ARCHIVED_DIR"; do
            if [ -d "$dir" ]; then
                for projeto_path in "$dir"/*; do
                    [ -e "$projeto_path" ] || continue
                    if [ -d "$projeto_path" ]; then
                        local projeto_nome=$(basename "$projeto_path")

                        # Fuzzy match: case-insensitive
                        local nome_lower=$(echo "$nome" | tr '[:upper:]' '[:lower:]')
                        local projeto_lower=$(echo "$projeto_nome" | tr '[:upper:]' '[:lower:]')

                        # Substring simples
                        if [[ "$projeto_lower" == *"$nome_lower"* ]]; then
                            encontrados+=("$projeto_nome")
                            encontrados_paths+=("$projeto_path")
                        fi
                    fi
                done
            fi
        done

        # Se encontrou exatamente um match
        if [ ${#encontrados[@]} -eq 1 ]; then
            nome_encontrado="${encontrados[0]}"
            projeto_dir="${encontrados_paths[0]}"
            echo -e "${GREEN}→ Encontrado: $nome_encontrado${NC}"
        # Se encontrou múltiplos matches
        elif [ ${#encontrados[@]} -gt 1 ]; then
            echo -e "${YELLOW}Múltiplos projetos encontrados para '$nome':${NC}"
            for i in "${!encontrados[@]}"; do
                echo -e "  $((i+1))) ${encontrados[$i]}"
            done

            read -p "Escolha o número [1]: " escolha
            escolha=${escolha:-1}

            if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le ${#encontrados[@]} ]; then
                nome_encontrado="${encontrados[$((escolha-1))]}"
                projeto_dir="${encontrados_paths[$((escolha-1))]}"
            else
                echo -e "${RED}Escolha inválida${NC}"
                return 1
            fi
        else
            # Não encontrou nada
            echo -e "${RED}Projeto não encontrado: $nome${NC}"
            echo -e "${BLUE}Projetos disponíveis:${NC}"
            _projeto_listar
            return 1
        fi
    fi

    # Marcar que está em um projeto (antes de entrar, para o jail funcionar)
    export PROJETO_ATUAL="$nome_encontrado"
    export PROJETO_ATUAL_PATH="$projeto_dir"

    # Entrar no projeto (usando builtin para evitar jail durante entrada)
    builtin cd "$projeto_dir"

    # Carregar ambiente se existir (com validação de segurança)
    if [ -f ".projeto-env" ]; then
        if _projeto_validar_env_file ".projeto-env"; then
            source .projeto-env
        else
            echo -e "${YELLOW}⚠ .projeto-env contém comandos potencialmente perigosos, ignorado${NC}"
            echo -e "${GREEN}Entrou no projeto: $nome_encontrado${NC}"
        fi
    else
        echo -e "${GREEN}Entrou no projeto: $nome_encontrado${NC}"
    fi

    # Mostrar informações (leitura segura de config, sem source)
    if [ -f ".projeto-config" ]; then
        _projeto_carregar_config ".projeto-config"
        echo -e "${BLUE}Tipo: $PROJETO_TIPO | Criado: $PROJETO_CRIADO${NC}"
    fi

    # Verificar git status se for repo
    if [ -d ".git" ]; then
        echo -e "${BLUE}Git:${NC}"
        git status -sb 2>/dev/null || true
    fi

    # Ativar jail para restringir navegação
    _projeto_ativar_jail

    # Ativar perfil isolado
    _projeto_ativar_perfil

    echo -e "${CYAN}🔒 Navegação restrita ao projeto (use 'projeto sair' para sair)${NC}"
}

# ============================================
# SAIR DO PROJETO
# ============================================

_projeto_sair() {
    if [ -z "$PROJETO_ATUAL" ]; then
        echo -e "${YELLOW}Você não está em nenhum projeto${NC}"
        return 0
    fi

    local projeto_anterior="$PROJETO_ATUAL"

    # Guardar HOME original antes de desativar perfil (HOME foi alterado pelo perfil)
    local home_original="${_PROJETO_ORIG_HOME:-$HOME}"

    # Desativar perfil isolado (restaura HOME, PS1, PATH, etc.)
    _projeto_desativar_perfil

    # Desativar jail (antes de cd)
    _projeto_desativar_jail

    # Desativar ambiente virtual Python se estiver ativo
    if [ -n "$VIRTUAL_ENV" ]; then
        deactivate 2>/dev/null || true
    fi

    # Limpar variáveis de ambiente do projeto
    unset PROJETO_ATUAL
    unset PROJETO_ATUAL_PATH
    unset PROJETO_NOME
    unset PROJETO_ROOT
    unset PROJETO_TIPO
    unset PROJETO_CRIADO
    unset PROJETO_LINGUAGEM
    unset PROJETO_IMPORTADO
    unset PROJETO_REPO

    # Voltar para home (agora sem restrições, usando HOME já restaurado)
    builtin cd "$home_original"

    echo -e "${GREEN}✓ Saiu do projeto: $projeto_anterior${NC}"
    echo -e "${CYAN}🔓 Navegação livre restaurada${NC}"
}

# ============================================
# LISTAR PROJETOS
# ============================================

_projeto_listar() {
    local filtro="$1"

    echo -e "${GREEN}=== Projetos Ativos ===${NC}"
    if [ -d "$ACTIVE_DIR" ]; then
        ls -1 "$ACTIVE_DIR" 2>/dev/null | while read proj; do
            echo -e "  ${BLUE}→${NC} $proj"
        done || echo -e "  ${YELLOW}(vazio)${NC}"
    fi

    echo -e "\n${YELLOW}=== Projetos Pessoais ===${NC}"
    if [ -d "$PERSONAL_DIR" ]; then
        ls -1 "$PERSONAL_DIR" 2>/dev/null | while read proj; do
            echo -e "  ${BLUE}→${NC} $proj"
        done || echo -e "  ${YELLOW}(vazio)${NC}"
    fi

    echo -e "\n${RED}=== Projetos Arquivados ===${NC}"
    if [ -d "$ARCHIVED_DIR" ]; then
        ls -1 "$ARCHIVED_DIR" 2>/dev/null | while read proj; do
            echo -e "  ${BLUE}→${NC} $proj"
        done || echo -e "  ${YELLOW}(vazio)${NC}"
    fi
}

# ============================================
# MOVER PROJETO
# ============================================

_projeto_mover() {
    local nome="$1"
    local destino="$2"

    if [ -z "$nome" ] || [ -z "$destino" ]; then
        echo -e "${RED}Erro: Especifique nome e destino${NC}"
        echo "Uso: projeto mover --nome-do-projeto active|personal|archived"
        return 1
    fi

    # Encontrar projeto
    local origem=""
    if [ -d "$ACTIVE_DIR/$nome" ]; then
        origem="$ACTIVE_DIR/$nome"
    elif [ -d "$PERSONAL_DIR/$nome" ]; then
        origem="$PERSONAL_DIR/$nome"
    elif [ -d "$ARCHIVED_DIR/$nome" ]; then
        origem="$ARCHIVED_DIR/$nome"
    else
        echo -e "${RED}Projeto não encontrado: $nome${NC}"
        return 1
    fi

    # Determinar destino
    local destino_dir=""
    case "$destino" in
        active) destino_dir="$ACTIVE_DIR" ;;
        personal) destino_dir="$PERSONAL_DIR" ;;
        archived) destino_dir="$ARCHIVED_DIR" ;;
        *)
            echo -e "${RED}Destino inválido: $destino${NC}"
            echo "Use: active, personal ou archived"
            return 1
            ;;
    esac

    if [ -d "$destino_dir/$nome" ]; then
        echo -e "${RED}Projeto já existe no destino${NC}"
        return 1
    fi

    mv "$origem" "$destino_dir/"

    # Atualizar config
    if [ -f "$destino_dir/$nome/.projeto-config" ]; then
        sed -i "s@PROJETO_TIPO=.*@PROJETO_TIPO=\"$destino\"@" "$destino_dir/$nome/.projeto-config"
    fi

    echo -e "${GREEN}✓ Projeto movido para $destino${NC}"
}

# ============================================
# ARQUIVAR PROJETO
# ============================================

_projeto_arquivar() {
    local nome="$1"

    if [ -z "$nome" ]; then
        echo -e "${RED}Erro: Nome do projeto não especificado${NC}"
        return 1
    fi

    _projeto_mover "$nome" "archived"
}

# ============================================
# REMOVER PROJETO
# ============================================

_projeto_remover() {
    local nome="$1"

    if [ -z "$nome" ]; then
        echo -e "${RED}Erro: Nome do projeto não especificado${NC}"
        return 1
    fi

    # Encontrar projeto
    local projeto_dir=""
    if [ -d "$ACTIVE_DIR/$nome" ]; then
        projeto_dir="$ACTIVE_DIR/$nome"
    elif [ -d "$PERSONAL_DIR/$nome" ]; then
        projeto_dir="$PERSONAL_DIR/$nome"
    elif [ -d "$ARCHIVED_DIR/$nome" ]; then
        projeto_dir="$ARCHIVED_DIR/$nome"
    else
        echo -e "${RED}Projeto não encontrado: $nome${NC}"
        return 1
    fi

    # Validar que o path é seguro antes de deletar
    if [ -z "$projeto_dir" ]; then
        echo -e "${RED}Erro interno: caminho do projeto vazio${NC}"
        return 1
    fi

    local projeto_dir_real
    projeto_dir_real=$(realpath -m "$projeto_dir" 2>/dev/null)
    local projects_root_real
    projects_root_real=$(realpath -m "$PROJECTS_ROOT" 2>/dev/null)

    if [[ "$projeto_dir_real" != "$projects_root_real/"* ]]; then
        echo -e "${RED}Erro: caminho do projeto está fora de PROJECTS_ROOT - operação bloqueada${NC}"
        return 1
    fi

    echo -e "${YELLOW}ATENÇÃO: Isso removerá permanentemente o projeto!${NC}"
    echo -e "Projeto: ${RED}$nome${NC}"
    echo -e "Local: $projeto_dir"
    read -p "Tem certeza? Digite 'sim' para confirmar: " confirmacao

    if [ "$confirmacao" = "sim" ]; then
        rm -rf "$projeto_dir"
        echo -e "${GREEN}✓ Projeto removido${NC}"
    else
        echo -e "${BLUE}Operação cancelada${NC}"
    fi
}

# ============================================
# INFO DO PROJETO
# ============================================

_projeto_info() {
    local nome="$1"

    if [ -z "$nome" ]; then
        echo -e "${RED}Erro: Nome do projeto não especificado${NC}"
        return 1
    fi

    # Encontrar projeto
    local projeto_dir=""
    local tipo=""

    if [ -d "$ACTIVE_DIR/$nome" ]; then
        projeto_dir="$ACTIVE_DIR/$nome"
        tipo="active"
    elif [ -d "$PERSONAL_DIR/$nome" ]; then
        projeto_dir="$PERSONAL_DIR/$nome"
        tipo="personal"
    elif [ -d "$ARCHIVED_DIR/$nome" ]; then
        projeto_dir="$ARCHIVED_DIR/$nome"
        tipo="archived"
    else
        echo -e "${RED}Projeto não encontrado: $nome${NC}"
        return 1
    fi

    echo -e "${GREEN}=== Informações do Projeto ===${NC}"
    echo -e "Nome: ${BLUE}$nome${NC}"
    echo -e "Tipo: ${BLUE}$tipo${NC}"
    echo -e "Caminho: $projeto_dir"

    if [ -f "$projeto_dir/.projeto-config" ]; then
        echo -e "\n${GREEN}=== Configuração ===${NC}"
        cat "$projeto_dir/.projeto-config"
    fi

    echo -e "\n${GREEN}=== Estrutura ===${NC}"
    if command -v tree &> /dev/null; then
        tree -L 2 -a "$projeto_dir"
    else
        ls -lh "$projeto_dir" 2>/dev/null | tail -n +2
    fi

    if [ -d "$projeto_dir/.git" ]; then
        echo -e "\n${GREEN}=== Git ===${NC}"
        git -C "$projeto_dir" log --oneline -5 2>/dev/null || echo "Sem commits"
    fi
}

# ============================================
# IMPORTAR DO GITHUB
# ============================================

_projeto_importar() {
    local repo_url="$1"

    if [ -z "$repo_url" ]; then
        # Verificar se gh está autenticado
        if ! command -v gh &>/dev/null; then
            echo -e "${RED}Erro: gh CLI não está instalado${NC}"
            echo "Instale com: apt install gh"
            return 1
        fi
        if ! gh auth status &>/dev/null; then
            echo -e "${RED}Erro: gh CLI não está autenticado${NC}"
            echo "Execute: gh auth login"
            return 1
        fi
        if ! command -v fzf &>/dev/null; then
            echo -e "${RED}Erro: fzf não está instalado${NC}"
            echo "Instale com: apt install fzf"
            return 1
        fi

        echo -e "${BLUE}Buscando seus repositórios no GitHub...${NC}"
        local repos
        repos=$(gh repo list --limit 100 --json nameWithOwner,description,isPrivate,updatedAt \
            --template '{{range .}}{{.nameWithOwner}}{{"\t"}}{{if .isPrivate}}[privado]{{else}}[público]{{end}} {{.description}}{{"\n"}}{{end}}' 2>&1)

        if [ $? -ne 0 ] || [ -z "$repos" ]; then
            echo -e "${RED}Erro ao buscar repositórios ou nenhum repositório encontrado${NC}"
            return 1
        fi

        local escolha
        escolha=$(echo "$repos" | fzf --height 40% --reverse --prompt="Escolha um repositório: " \
            --header="↑↓ navegar | Enter selecionar | Esc cancelar" \
            --delimiter='\t' --with-nth=1,2 --tabstop=4 --ansi)

        if [ -z "$escolha" ]; then
            echo -e "${BLUE}Operação cancelada${NC}"
            return 0
        fi

        # Extrair owner/repo (primeira coluna antes do tab)
        local repo_name_with_owner
        repo_name_with_owner=$(echo "$escolha" | cut -f1)
        repo_url="https://github.com/${repo_name_with_owner}.git"
        echo -e "${GREEN}Selecionado: ${repo_name_with_owner}${NC}"
    fi

    # Detectar owner/repo para gh repo clone (se veio de URL, extrair)
    local gh_repo=""
    if [ -n "$repo_name_with_owner" ]; then
        gh_repo="$repo_name_with_owner"
    elif [[ "$repo_url" =~ github\.com[:/]([^/]+/[^/.]+) ]]; then
        gh_repo="${BASH_REMATCH[1]}"
    fi

    # Extrair nome do repo
    local repo_name=$(basename "$repo_url" .git)

    # Validar nome extraído
    if ! _projeto_sanitizar_nome "$repo_name"; then
        echo -e "${YELLOW}Nome extraído do URL é inválido: $repo_name${NC}"
        read -p "Informe um nome válido para o projeto: " repo_name
        if ! _projeto_sanitizar_nome "$repo_name"; then
            return 1
        fi
    fi

    # Perguntar onde salvar
    echo -e "${BLUE}Onde salvar o projeto?${NC}"
    echo "1) active (padrão)"
    echo "2) personal"
    echo "3) archived"
    read -p "Escolha [1]: " tipo_escolha

    local tipo="active"
    case "${tipo_escolha:-1}" in
        1) tipo="active" ;;
        2) tipo="personal" ;;
        3) tipo="archived" ;;
        *) tipo="active" ;;
    esac

    local projeto_dir="$PROJECTS_ROOT/$tipo/$repo_name"

    # Verificar se já existe
    if [ -d "$projeto_dir" ]; then
        echo -e "${YELLOW}Projeto já existe: $projeto_dir${NC}"
        read -p "Deseja sobrescrever? (s/N): " sobrescrever
        if [[ ! "$sobrescrever" =~ ^[Ss]$ ]]; then
            echo -e "${BLUE}Operação cancelada${NC}"
            return 1
        fi
        rm -rf "$projeto_dir"
    fi

    echo -e "${GREEN}Clonando repositório...${NC}"

    # Clonar usando gh se disponível e repo GitHub, senão git clone
    if [ -n "$gh_repo" ] && command -v gh &>/dev/null && gh auth status &>/dev/null; then
        if ! gh repo clone "$gh_repo" "$projeto_dir"; then
            echo -e "${RED}Erro ao clonar repositório${NC}"
            return 1
        fi
    else
        if ! git clone "$repo_url" "$projeto_dir"; then
            echo -e "${RED}Erro ao clonar repositório${NC}"
            return 1
        fi
    fi

    # Criar arquivos de configuração do projeto
    cat > "$projeto_dir/.projeto-config" <<EOF
# Configuração do Projeto
PROJETO_NOME="$repo_name"
PROJETO_TIPO="$tipo"
PROJETO_CRIADO="$(date +"%Y-%m-%d %H:%M:%S")"
PROJETO_IMPORTADO="true"
PROJETO_REPO="$repo_url"
EOF

    # Criar script de ambiente se não existir
    # Se o repo clonado já traz um .projeto-env, avisar o usuário
    if [ -f "$projeto_dir/.projeto-env" ]; then
        echo -e "${YELLOW}⚠ O repositório clonado contém um .projeto-env${NC}"
        if ! _projeto_validar_env_file "$projeto_dir/.projeto-env"; then
            echo -e "${RED}⚠ O arquivo .projeto-env contém comandos potencialmente perigosos!${NC}"
            read -p "Deseja usar o .projeto-env do repositório? (s/N): " usar_env
            if [[ ! "$usar_env" =~ ^[Ss]$ ]]; then
                echo -e "${BLUE}Substituindo por .projeto-env seguro${NC}"
                rm -f "$projeto_dir/.projeto-env"
            fi
        fi
    fi
    if [ ! -f "$projeto_dir/.projeto-env" ]; then
        cat > "$projeto_dir/.projeto-env" <<ENVEOF
#!/bin/bash
# Ambiente do projeto $repo_name

export PROJETO_NOME="$repo_name"
export PROJETO_ROOT="$projeto_dir"

# Ativar ambiente virtual se existir
if [ -d "\$PROJETO_ROOT/venv" ]; then
    source "\$PROJETO_ROOT/venv/bin/activate"
fi

echo -e "\033[0;32mAmbiente do projeto $repo_name ativado\033[0m"
ENVEOF
        chmod +x "$projeto_dir/.projeto-env"
    fi

    echo -e "${GREEN}✓ Repositório '$repo_name' importado com sucesso!${NC}"
    echo -e "${BLUE}Caminho: $projeto_dir${NC}"
    echo -e "${BLUE}Entre no projeto com: projeto --$repo_name${NC}\n"

    # Detectar tipo de projeto e dar dicas
    if [ -f "$projeto_dir/package.json" ]; then
        echo -e "${YELLOW}📦 Projeto Node.js detectado${NC}"
        echo -e "   Sugestão: npm install"
    fi

    if [ -f "$projeto_dir/requirements.txt" ]; then
        echo -e "${YELLOW}🐍 Projeto Python detectado${NC}"
        echo -e "   Sugestão: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
    fi

    if [ -f "$projeto_dir/Cargo.toml" ]; then
        echo -e "${YELLOW}🦀 Projeto Rust detectado${NC}"
        echo -e "   Sugestão: cargo build"
    fi

    if [ -f "$projeto_dir/go.mod" ]; then
        echo -e "${YELLOW}🐹 Projeto Go detectado${NC}"
        echo -e "   Sugestão: go mod download"
    fi

    # Perguntar se quer entrar
    echo ""
    read -p "Entrar no projeto agora? [S/n]: " entrar
    if [[ "${entrar:-s}" =~ ^[Ss]$ ]]; then
        _projeto_entrar "$repo_name"
    fi
}

# ============================================
# AJUDA
# ============================================

_projeto_help() {
    cat <<EOF
${GREEN}=== Sistema de Gerenciamento de Projetos ===${NC}

${BLUE}Uso:${NC}
  projeto criar --${YELLOW}nome${NC}              Criar novo projeto
  projeto importar ${YELLOW}url${NC}              Importar repositório Git
  projeto --${YELLOW}nome${NC}                    Entrar no projeto
  projeto sair                        Sair do projeto atual
  projeto listar                      Listar todos os projetos
  projeto mover --${YELLOW}nome${NC} ${YELLOW}destino${NC}      Mover projeto (active/personal/archived)
  projeto arquivar --${YELLOW}nome${NC}           Arquivar projeto
  projeto remover --${YELLOW}nome${NC}            Remover projeto (cuidado!)
  projeto info --${YELLOW}nome${NC}               Ver informações do projeto
  projeto perfil                      Configurar perfil (git identity)
  projeto help                        Mostrar esta ajuda

${BLUE}Exemplos:${NC}
  projeto criar --meu-app             Criar projeto 'meu-app'
  projeto importar https://...        Importar repo do GitHub
  projeto --meu-app                   Entrar no projeto 'meu-app'
  p meu-app                           Atalho rápido para entrar
  projeto sair                        Sair do projeto atual
  projeto mover --meu-app archived    Arquivar 'meu-app'
  projeto listar                      Ver todos os projetos

${BLUE}Estrutura:${NC}
  ~/projects/active/       Projetos ativos
  ~/projects/personal/     Projetos pessoais
  ~/projects/archived/     Projetos arquivados

${BLUE}Atalho rápido:${NC}
  ${CYAN}p${NC} ${YELLOW}nome${NC}                          Entrar rapidamente no projeto
  ${CYAN}p${NC}                               Listar todos (se tiver fzf instalado)
EOF
}

# ============================================
# ATALHO RÁPIDO: p
# ============================================

p() {
    _projeto_init

    [ -n "$ZSH_VERSION" ] && setopt local_options KSH_ARRAYS

    local busca="$1"

    # Se não passou argumento, mostrar menu interativo
    if [ -z "$busca" ]; then
        # Verificar se fzf está disponível
        if command -v fzf &> /dev/null; then
            echo -e "${BLUE}Selecione um projeto:${NC}"

            # Coletar todos os projetos com seus tipos
            local projetos=()
            for dir in "$ACTIVE_DIR" "$PERSONAL_DIR" "$ARCHIVED_DIR"; do
                if [ -d "$dir" ]; then
                    local tipo=$(basename "$dir")
                    for projeto_path in "$dir"/*; do
                        [ -e "$projeto_path" ] || continue
                        if [ -d "$projeto_path" ]; then
                            local nome=$(basename "$projeto_path")
                            projetos+=("$tipo/$nome")
                        fi
                    done
                fi
            done

            if [ ${#projetos[@]} -eq 0 ]; then
                echo -e "${YELLOW}Nenhum projeto encontrado${NC}"
                echo -e "${BLUE}Crie um novo projeto com: projeto criar --nome${NC}"
                return 1
            fi

            # Usar fzf para seleção
            local projeto_selecionado=$(printf '%s\n' "${projetos[@]}" | fzf \
                --height 40% \
                --reverse \
                --border \
                --prompt="Projeto > " \
                --preview 'tipo=$(echo {} | cut -d/ -f1); nome=$(echo {} | cut -d/ -f2); cat ~/projects/$tipo/$nome/README.md 2>/dev/null || echo "Sem README disponível"' \
                --preview-window=right:60% \
                --header="↑↓ navegar | Enter selecionar | Esc sair")

            if [ -n "$projeto_selecionado" ]; then
                local nome=$(echo "$projeto_selecionado" | cut -d'/' -f2)
                _projeto_entrar "$nome"
            else
                echo -e "${YELLOW}Nenhum projeto selecionado${NC}"
                return 1
            fi
        else
            # Fallback: listar projetos se fzf não estiver disponível
            echo -e "${BLUE}Projetos disponíveis:${NC}"
            _projeto_listar
            echo -e "\n${YELLOW}Dica: Instale 'fzf' para um menu interativo!${NC}"
            echo -e "${BLUE}Use: p <nome-do-projeto> para entrar diretamente${NC}"
        fi
        return 0
    fi

    # Buscar projeto
    local encontrados=()
    local encontrados_paths=()
    local exato=""

    if [ -n "$BASH_VERSION" ]; then
        shopt -s nullglob
    elif [ -n "$ZSH_VERSION" ]; then
        setopt local_options nullglob
    fi

    for dir in "$ACTIVE_DIR" "$PERSONAL_DIR" "$ARCHIVED_DIR"; do
        if [ -d "$dir" ]; then
            for projeto_path in "$dir"/*; do
                [ -e "$projeto_path" ] || continue
                if [ -d "$projeto_path" ]; then
                    local projeto_nome=$(basename "$projeto_path")

                    # Match exato
                    if [ "$projeto_nome" = "$busca" ]; then
                        exato="$projeto_nome"
                        break 2
                    fi

                    # Match parcial (case insensitive)
                    local busca_lower=$(echo "$busca" | tr '[:upper:]' '[:lower:]')
                    local projeto_lower=$(echo "$projeto_nome" | tr '[:upper:]' '[:lower:]')

                    if [[ "$projeto_lower" == *"$busca_lower"* ]]; then
                        encontrados+=("$projeto_nome")
                        encontrados_paths+=("$projeto_path")
                    fi
                fi
            done
        fi
    done

    # Se encontrou exato, entra
    if [ -n "$exato" ]; then
        _projeto_entrar "$exato"
        return 0
    fi

    # Se encontrou um único match parcial, entra
    if [ ${#encontrados[@]} -eq 1 ]; then
        echo -e "${GREEN}→ Entrando em: ${encontrados[0]}${NC}"
        _projeto_entrar "${encontrados[0]}"
        return 0
    fi

    # Se encontrou múltiplos
    if [ ${#encontrados[@]} -gt 1 ]; then
        echo -e "${YELLOW}Múltiplos projetos encontrados para '$busca':${NC}"

        # Usar fzf se disponível
        if command -v fzf &> /dev/null; then
            local escolhido=$(printf '%s\n' "${encontrados[@]}" | fzf \
                --height 40% \
                --reverse \
                --border \
                --prompt="Escolha > " \
                --header="Encontrados: ${#encontrados[@]} projetos")

            if [ -n "$escolhido" ]; then
                _projeto_entrar "$escolhido"
            else
                echo -e "${YELLOW}Nenhum projeto selecionado${NC}"
                return 1
            fi
        else
            # Fallback: menu numerado
            for i in "${!encontrados[@]}"; do
                echo -e "  $((i+1))) ${encontrados[$i]}"
            done
            read -p "Escolha [1]: " escolha
            escolha=${escolha:-1}
            if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le ${#encontrados[@]} ]; then
                _projeto_entrar "${encontrados[$((escolha-1))]}"
            else
                echo -e "${RED}Escolha inválida${NC}"
                return 1
            fi
        fi
        return 0
    fi

    # Não encontrou nada
    echo -e "${RED}Projeto não encontrado: $busca${NC}"
    echo -e "${BLUE}Projetos disponíveis:${NC}"
    _projeto_listar
    return 1
}

# ============================================
# AUTOCOMPLETION - BASH
# ============================================

_projeto_completions_bash() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    local comandos="criar importar entrar sair listar mover arquivar remover info help"

    if [ $COMP_CWORD -eq 1 ]; then
        local projetos=$(ls -1 "$ACTIVE_DIR" "$PERSONAL_DIR" "$ARCHIVED_DIR" 2>/dev/null | sed 's/^/--/')
        COMPREPLY=( $(compgen -W "$comandos $projetos" -- "$cur") )
    elif [[ "$prev" =~ ^(entrar|mover|arquivar|remover|info|criar)$ ]]; then
        local projetos=$(ls -1 "$ACTIVE_DIR" "$PERSONAL_DIR" "$ARCHIVED_DIR" 2>/dev/null | sed 's/^/--/')
        COMPREPLY=( $(compgen -W "$projetos" -- "$cur") )
    fi
}

_p_completions_bash() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local projetos=$(ls -1 "$ACTIVE_DIR" "$PERSONAL_DIR" "$ARCHIVED_DIR" 2>/dev/null)
    COMPREPLY=( $(compgen -W "$projetos" -- "$cur") )
}

# ============================================
# AUTOCOMPLETION - ZSH
# ============================================

_projeto_completions_zsh() {
    local -a comandos projetos

    comandos=(
        'criar:Criar novo projeto'
        'importar:Importar repositório Git'
        'entrar:Entrar no projeto'
        'sair:Sair do projeto atual'
        'listar:Listar todos os projetos'
        'mover:Mover projeto'
        'arquivar:Arquivar projeto'
        'remover:Remover projeto'
        'info:Ver informações do projeto'
        'help:Mostrar ajuda'
    )

    if [ -d "$ACTIVE_DIR" ] || [ -d "$PERSONAL_DIR" ] || [ -d "$ARCHIVED_DIR" ]; then
        projetos=($(ls -1 "$ACTIVE_DIR" "$PERSONAL_DIR" "$ARCHIVED_DIR" 2>/dev/null | sed 's/^/--/'))
    fi

    _arguments \
        '1: :->command' \
        '*::arg:->args' && return 0

    case $state in
        command)
            _describe 'comando' comandos
            _describe 'projeto' projetos
            ;;
        args)
            case $words[1] in
                entrar|mover|arquivar|remover|info|criar)
                    _describe 'projeto' projetos
                    ;;
            esac
            ;;
    esac
}

_p_completions_zsh() {
    local -a projetos
    if [ -d "$ACTIVE_DIR" ] || [ -d "$PERSONAL_DIR" ] || [ -d "$ARCHIVED_DIR" ]; then
        projetos=($(ls -1 "$ACTIVE_DIR" "$PERSONAL_DIR" "$ARCHIVED_DIR" 2>/dev/null))
    fi
    _describe 'projeto' projetos
}

# ============================================
# REGISTRAR AUTOCOMPLETION
# ============================================

if [ -n "$BASH_VERSION" ]; then
    complete -F _projeto_completions_bash projeto
    complete -F _p_completions_bash p
    export -f projeto
    export -f p
elif [ -n "$ZSH_VERSION" ]; then
    if ! type compdef >/dev/null 2>&1; then
        autoload -Uz compinit
        compinit -D 2>/dev/null
    fi
    compdef _projeto_completions_zsh projeto 2>/dev/null
    compdef _p_completions_zsh p 2>/dev/null
fi

# ============================================
# EXECUÇÃO DIRETA (não via source)
# ============================================

if [ -n "$BASH_VERSION" ]; then
    if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
        projeto "$@"
    fi
elif [ -n "$ZSH_VERSION" ]; then
    if [[ "${ZSH_EVAL_CONTEXT}" != *:file ]]; then
        projeto "$@"
    fi
fi
