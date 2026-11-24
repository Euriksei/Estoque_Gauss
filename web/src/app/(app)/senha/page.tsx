import { NovaSenhaForm } from "@/components/NovaSenhaForm";

// Troca de senha de quem está logado. Disponível para todos os perfis.
export default function TrocarSenha() {
  return (
    <div className="mx-auto max-w-sm">
      <h1 className="mb-4 text-lg font-semibold">Trocar senha</h1>
      <div className="card">
        <NovaSenhaForm depois="/senha" />
      </div>
    </div>
  );
}
