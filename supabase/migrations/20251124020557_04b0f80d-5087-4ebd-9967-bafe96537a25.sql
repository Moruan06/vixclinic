-- FASE 1: LIMPEZA DO BANCO DE DADOS

-- 1. Remover tabelas desnecessárias
DROP TABLE IF EXISTS public.user_roles CASCADE;
DROP TABLE IF EXISTS public.administradores CASCADE;
DROP TABLE IF EXISTS public.configuracao_sistema CASCADE;

-- 2. Remover função de verificação de role
DROP FUNCTION IF EXISTS public.has_role(uuid, app_role) CASCADE;

-- 3. Remover enum de roles
DROP TYPE IF EXISTS public.app_role CASCADE;

-- 4. Simplificar RLS Policies na tabela funcionario
-- Remover policies antigas
DROP POLICY IF EXISTS "Admins podem gerenciar funcionarios" ON funcionario;
DROP POLICY IF EXISTS "Admins podem inserir funcionarios" ON funcionario;
DROP POLICY IF EXISTS "Admins podem ver funcionarios" ON funcionario;
DROP POLICY IF EXISTS "Admins podem atualizar funcionarios" ON funcionario;
DROP POLICY IF EXISTS "Admins podem deletar funcionarios" ON funcionario;

-- Criar policy simples: qualquer usuário autenticado tem acesso total
CREATE POLICY "Usuarios autenticados podem gerenciar funcionarios"
ON funcionario FOR ALL
TO authenticated
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

-- 5. Criar função RPC para verificar se existem usuários (usada pela página /auth)
CREATE OR REPLACE FUNCTION public.check_users_exist()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM auth.users LIMIT 1);
END;
$$;