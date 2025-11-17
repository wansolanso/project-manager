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
# PROJETO JAIL - RESTRIÇÃO DE NAVEGAÇÃO
# ============================================

# Override do comando cd para restringir navegação
_projeto_cd_jail() {
    local target="$1"

    # Se não estiver em um projeto, cd normal
    if [ -z "$PROJETO_ATUAL_PATH" ]; then
        builtin cd "$@"
        return $?
    fi

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

    # Verificar se o destino está dentro do projeto
    local destino_real=$(realpath -m "$destino" 2>/dev/null || echo "$destino")
    local projeto_real=$(realpath -m "$PROJETO_ATUAL_PATH" 2>/dev/null || echo "$PROJETO_ATUAL_PATH")

    # Comparar caminhos
    if [[ "$destino_real" == "$projeto_real"* ]]; then
        # Destino está dentro do projeto - permitir
        builtin cd "$@"
        return $?
    else
        # Destino está fora do projeto - bloquear
        echo -e "${RED}✗ Não é possível navegar para fora do projeto '$PROJETO_ATUAL'${NC}"
        echo -e "${YELLOW}Caminho bloqueado: $target${NC}"
        echo -e "${YELLOW}Use 'projeto sair' para sair do projeto${NC}"
        return 1
    fi
}

# Ativar/desativar jail
_projeto_ativar_jail() {
    if [ -n "$BASH_VERSION" ]; then
        # Bash: usar alias
        alias cd='_projeto_cd_jail'
    elif [ -n "$ZSH_VERSION" ]; then
        # Zsh: criar função que sobrescreve cd
        cd() { _projeto_cd_jail "$@"; }
    fi
    export PROJETO_JAIL_ATIVO="1"
}

_projeto_desativar_jail() {
    if [ -n "$BASH_VERSION" ]; then
        unalias cd 2>/dev/null
    elif [ -n "$ZSH_VERSION" ]; then
        unfunction cd 2>/dev/null
    fi
    unset PROJETO_JAIL_ATIVO
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
EOF

    # Criar configuração do projeto
    cat > "$projeto_dir/.projeto-config" <<EOF
# Configuração do Projeto
PROJETO_NOME="$nome"
PROJETO_TIPO="$tipo"
PROJETO_CRIADO="$(date +"%Y-%m-%d %H:%M:%S")"
PROJETO_LINGUAGEM=""
PROJETO_VENV=""
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

    # Substituir placeholders
    sed -i "s|NOME_PLACEHOLDER|$nome|g" "$projeto_dir/.projeto-env"
    sed -i "s|DIR_PLACEHOLDER|$projeto_dir|g" "$projeto_dir/.projeto-env"
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

    # Carregar ambiente se existir
    if [ -f ".projeto-env" ]; then
        source .projeto-env
    else
        echo -e "${GREEN}Entrou no projeto: $nome_encontrado${NC}"
    fi

    # Mostrar informações
    if [ -f ".projeto-config" ]; then
        source .projeto-config
        echo -e "${BLUE}Tipo: $PROJETO_TIPO | Criado: $PROJETO_CRIADO${NC}"
    fi

    # Verificar git status se for repo
    if [ -d ".git" ]; then
        echo -e "${BLUE}Git:${NC}"
        git status -sb 2>/dev/null || true
    fi

    # Ativar jail para restringir navegação
    _projeto_ativar_jail
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

    # Desativar jail primeiro (antes de cd)
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

    # Voltar para home (agora sem restrições)
    builtin cd "$HOME"

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
        sed -i "s/PROJETO_TIPO=.*/PROJETO_TIPO=\"$destino\"/" "$destino_dir/$nome/.projeto-config"
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
        cd "$projeto_dir"
        git log --oneline -5 2>/dev/null || echo "Sem commits"
    fi
}

# ============================================
# IMPORTAR DO GITHUB
# ============================================

_projeto_importar() {
    local repo_url="$1"

    if [ -z "$repo_url" ]; then
        echo -e "${RED}Erro: URL do repositório não especificada${NC}"
        echo "Uso: projeto importar <url-do-repo>"
        echo "Exemplo: projeto importar https://github.com/usuario/repo"
        return 1
    fi

    # Extrair nome do repo
    local repo_name=$(basename "$repo_url" .git)

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

    # Clonar
    if ! git clone "$repo_url" "$projeto_dir"; then
        echo -e "${RED}Erro ao clonar repositório${NC}"
        return 1
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
