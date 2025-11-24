import React, { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { toast } from 'sonner';
import { z } from 'zod';
import { Stethoscope } from 'lucide-react';

// Schema para LOGIN (apenas email e senha)
const loginSchema = z.object({
  email: z.string().email('Email inválido'),
  senha: z.string().min(6, 'Senha deve ter no mínimo 6 caracteres'),
});

// Schema para CADASTRO (com confirmação de senha)
const signupSchema = z.object({
  email: z.string().email('Email inválido'),
  senha: z.string().min(6, 'Senha deve ter no mínimo 6 caracteres'),
  confirmarSenha: z.string().min(6, 'Confirmação de senha obrigatória')
}).refine((data) => data.senha === data.confirmarSenha, {
  message: 'As senhas não coincidem',
  path: ['confirmarSenha']
});

export const Auth = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const [loading, setLoading] = useState(false);
  const [isSignup, setIsSignup] = useState(false);
  const [checkingUsers, setCheckingUsers] = useState(true);
  const [formData, setFormData] = useState({
    email: '',
    senha: '',
    confirmarSenha: ''
  });
  const [errors, setErrors] = useState<Record<string, string>>({});

  useEffect(() => {
    checkExistingUsers();
  }, []);

  // Re-verificar quando voltar para a página /auth (após logout, por exemplo)
  useEffect(() => {
    if (location.pathname === '/auth') {
      checkExistingUsers();
    }
  }, [location.pathname]);

  const checkExistingUsers = async () => {
    try {
      const { data, error } = await supabase.rpc('check_users_exist');
      
      if (error) {
        console.error('Error checking users:', error);
        setIsSignup(false);
      } else {
        setIsSignup(!data);
      }
    } catch (error) {
      console.error('Error checking users:', error);
      setIsSignup(false);
    } finally {
      setCheckingUsers(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrors({});
    setLoading(true);

    try {
      // Validar com schema apropriado
      if (isSignup) {
        signupSchema.parse(formData);
      } else {
        loginSchema.parse({
          email: formData.email,
          senha: formData.senha
        });
      }

      if (isSignup) {
        const { error } = await supabase.auth.signUp({
          email: formData.email,
          password: formData.senha,
          options: {
            emailRedirectTo: `${window.location.origin}/`
          }
        });

        if (error) throw error;

        toast.success('Cadastro realizado com sucesso!');
        navigate('/');
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          email: formData.email,
          password: formData.senha
        });

        if (error) throw error;

        toast.success('Login realizado com sucesso!');
        navigate('/');
      }
    } catch (error: any) {
      console.error('Auth error:', error);
      
      if (error instanceof z.ZodError) {
        const fieldErrors: Record<string, string> = {};
        error.errors.forEach((err) => {
          if (err.path[0]) {
            fieldErrors[err.path[0] as string] = err.message;
          }
        });
        setErrors(fieldErrors);
      } else {
        // Mapear erros comuns do Supabase para mensagens em português
        let errorMessage = 'Erro na autenticação';
        
        if (error.message?.includes('Email not confirmed')) {
          errorMessage = 'Seu email ainda não foi confirmado. Verifique sua caixa de entrada.';
        } else if (error.message?.includes('Invalid login credentials')) {
          errorMessage = 'Email ou senha incorretos. Verifique seus dados e tente novamente.';
        } else if (error.message?.includes('User already registered')) {
          errorMessage = 'Este email já está cadastrado. Use o formulário de login.';
        } else if (error.message) {
          errorMessage = error.message;
        }
        
        toast.error(errorMessage);
      }
    } finally {
      setLoading(false);
    }
  };

  if (checkingUsers) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-medical-blue/10 to-medical-teal/10">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-medical-blue"></div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-medical-blue/10 to-medical-teal/10 p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1 text-center">
          <div className="flex justify-center mb-4">
            <div className="w-16 h-16 bg-medical-blue rounded-full flex items-center justify-center">
              <Stethoscope className="w-8 h-8 text-white" />
            </div>
          </div>
          <CardTitle className="text-2xl font-bold">
            {isSignup ? 'Configurar Sistema' : 'VixClinic'}
          </CardTitle>
          <CardDescription>
            {isSignup 
              ? 'Crie o primeiro acesso ao sistema. Esta conta terá acesso completo.'
              : 'Entre com seu email e senha para acessar o sistema.'
            }
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                placeholder="seu@email.com"
                value={formData.email}
                onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                required
              />
              {errors.email && (
                <p className="text-sm text-destructive">{errors.email}</p>
              )}
            </div>

            <div className="space-y-2">
              <Label htmlFor="senha">Senha</Label>
              <Input
                id="senha"
                type="password"
                placeholder="••••••••"
                value={formData.senha}
                onChange={(e) => setFormData({ ...formData, senha: e.target.value })}
                required
              />
              {errors.senha && (
                <p className="text-sm text-destructive">{errors.senha}</p>
              )}
            </div>

            {isSignup && (
              <div className="space-y-2">
                <Label htmlFor="confirmarSenha">Confirmar Senha</Label>
                <Input
                  id="confirmarSenha"
                  type="password"
                  placeholder="••••••••"
                  value={formData.confirmarSenha}
                  onChange={(e) => setFormData({ ...formData, confirmarSenha: e.target.value })}
                  required
                />
                {errors.confirmarSenha && (
                  <p className="text-sm text-destructive">{errors.confirmarSenha}</p>
                )}
              </div>
            )}

            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? 'Aguarde...' : (isSignup ? 'Criar Acesso' : 'Entrar')}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
};
