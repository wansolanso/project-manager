# Project Manager

Um sistema completo de gerenciamento de projetos para terminal (Bash/Zsh).

## Características

- **Organização automática** - Separa projetos em active, personal e archived
- **Navegação rápida** - Entre em projetos com `p nome` ou `projeto --nome`
- **Importação Git** - Clone repositórios direto para sua estrutura
- **Ambientes isolados** - Suporte automático para venv, nvm e variáveis de ambiente
- **Autocompletion** - Funciona em Bash e Zsh
- **Fuzzy search** - Encontre projetos digitando apenas parte do nome

## Instalação

```bash
# 1. Baixar o script
curl -O https://raw.githubusercontent.com/SEU-USUARIO/project-manager/main/projeto.sh

# 2. Mover para ~/bin/
mkdir -p ~/bin
mv projeto.sh ~/bin/projeto
chmod +x ~/bin/projeto

# 3. Adicionar ao shell (~/.bashrc ou ~/.zshrc)
echo 'source ~/bin/projeto' >> ~/.zshrc

# 4. Recarregar
source ~/.zshrc
```

## Uso

### Criar projeto

```bash
projeto criar --meu-app
```

Isso cria:
```
~/projects/active/meu-app/
├── src/
├── docs/
├── tests/
├── config/
├── README.md
├── .gitignore
├── .projeto-config
└── .projeto-env
```

### Entrar em projeto

```bash
# Forma completa
projeto --meu-app

# Atalho rápido
p meu-app

# Fuzzy search (encontra "meu-app" digitando apenas "app")
p app
```

### Importar repositório Git

```bash
projeto importar https://github.com/usuario/repo
```

### Gerenciar projetos

```bash
# Listar todos
projeto listar

# Ver informações
projeto info --meu-app

# Mover para pessoal
projeto mover --meu-app personal

# Arquivar
projeto arquivar --meu-app

# Remover
projeto remover --meu-app
```

### Sair do projeto

```bash
projeto sair
```

## Comandos Disponíveis

| Comando | Descrição |
|---------|-----------|
| `projeto criar --nome` | Criar novo projeto |
| `projeto importar url` | Importar repositório Git |
| `projeto --nome` | Entrar no projeto |
| `p nome` | Atalho rápido para entrar |
| `projeto sair` | Sair do projeto atual |
| `projeto listar` | Listar todos os projetos |
| `projeto mover --nome destino` | Mover projeto (active/personal/archived) |
| `projeto arquivar --nome` | Arquivar projeto |
| `projeto remover --nome` | Remover projeto |
| `projeto info --nome` | Ver informações do projeto |
| `projeto help` | Mostrar ajuda |

## Estrutura de Diretórios

```
~/projects/
├── active/       # Projetos em desenvolvimento ativo
├── personal/     # Projetos pessoais
└── archived/     # Projetos arquivados
```

## Recursos Avançados

### Ambientes Personalizados

Cada projeto tem um arquivo `.projeto-env` que é carregado automaticamente:

```bash
# .projeto-env
export DATABASE_URL="postgres://localhost/mydb"
export API_KEY="sua-chave"

# Ativar venv automaticamente
if [ -d "$PROJETO_ROOT/venv" ]; then
    source "$PROJETO_ROOT/venv/bin/activate"
fi

# Aliases específicos do projeto
alias test="python -m pytest"
alias run="npm start"
```

### Detecção Automática

O script detecta automaticamente o tipo de projeto:

- **Node.js** (`package.json`) - Sugere `npm install`
- **Python** (`requirements.txt`) - Sugere criar venv e instalar dependências
- **Rust** (`Cargo.toml`) - Sugere `cargo build`
- **Go** (`go.mod`) - Sugere `go mod download`

### Fuzzy Search

O comando `p` suporta busca inteligente:

```bash
# Match exato
p meu-projeto-web

# Match parcial
p web              # Encontra "meu-projeto-web"

# Múltiplos resultados - mostra menu de escolha
p app              # Lista todos com "app" no nome
```

## Configuração

Por padrão, os projetos ficam em `~/projects`. Para mudar:

```bash
export PROJECTS_ROOT="/seu/caminho/projetos"
```

## Compatibilidade

- ✅ Bash 4.0+
- ✅ Zsh 5.0+
- ✅ Linux
- ✅ macOS
- ✅ WSL

## Requisitos

- Git (para importar repositórios)
- Bash ou Zsh

## Licença

MIT

## Contribuindo

Contribuições são bem-vindas! Sinta-se à vontade para abrir issues ou pull requests.
