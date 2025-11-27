# 💉 VixClinic - Sistema de Gestão de Vacinação


> Sistema completo para gerenciamento de clínicas de vacinação, controle de estoque de imunizantes e agendamento de pacientes.

## 🔗 Links Rápidos & Demo

- **🌐 Deploy:** [Acessar Sistema](https://vixclinica.vercel.app/)
- **📺 Vídeo de Apresentação:** [Assistir no YouTube](https://youtu.be/Qfbgf06EcnQ)

### 🔑 Credenciais de Acesso (Admin)
Para testar todas as funcionalidades do sistema, utilize o login abaixo:

| Campo | Valor |
|-------|-------|
| **Login** | `adm@clinica.com` |
| **Senha** | `12345678` |

---

## 📋 Sobre o Projeto

O **VixClinic** é uma solução moderna desenvolvida para otimizar o fluxo de trabalho em clínicas de vacinação. O sistema permite o gerenciamento integral desde o cadastro de pacientes e funcionários até o controle rigoroso de lotes de vacinas e aplicação de doses.

### Principais Funcionalidades

- **📊 Dashboard Interativo**: Visão geral de métricas como vacinações do dia, lotes próximos ao vencimento e agendamentos pendentes.
- **👥 Gestão de Pacientes**: Cadastro completo com histórico clínico e de vacinação.
- **👨‍⚕️ Controle de Funcionários**: Gerenciamento de equipe com diferentes níveis de acesso (Administrador, Vacinador, Atendente).
- **📦 Controle de Estoque (Lotes)**: 
  - Rastreamento de lotes por validade e quantidade.
  - Bloqueio automático de lotes vencidos ou sem estoque.
  - Gestão de preços de compra e venda.
- **💉 Catálogo de Vacinas**: Cadastro de tipos de vacinas (Viral, Bacteriana, Outra) com definições de doses e intervalos.
- **YW Agendamentos**: Sistema de agendamento inteligente que reserva estoque automaticamente.
- **📝 Registro de Aplicação**: Fluxo de aplicação que baixa o estoque, atualiza o histórico do paciente e agenda próximas doses se necessário.
- **📈 Relatórios**: Geração de relatórios financeiros e operacionais.

---

## 🛠️ Tecnologias Utilizadas

O projeto foi construído utilizando uma stack moderna e performática:

### Frontend
- **[React](https://react.dev/)** (v18) com **[Vite](https://vitejs.dev/)**
- **[TypeScript](https://www.typescriptlang.org/)** para tipagem estática e segurança
- **[Tailwind CSS](https://tailwindcss.com/)** para estilização
- **[Shadcn/ui](https://ui.shadcn.com/)** & **[Radix UI](https://www.radix-ui.com/)** para componentes de interface acessíveis
- **[TanStack Query](https://tanstack.com/query/latest)** para gerenciamento de estado assíncrono
- **[React Hook Form](https://react-hook-form.com/)** + **[Zod](https://zod.dev/)** para formulários e validação
- **[Recharts](https://recharts.org/)** para visualização de dados

### Backend & Infraestrutura
- **[Supabase](https://supabase.com/)** (BaaS)
  - **Authentication**: Gestão de usuários e segurança JWT
  - **PostgreSQL**: Banco de dados relacional robusto
  - **Row Level Security (RLS)**: Políticas de segurança a nível de banco de dados

---
