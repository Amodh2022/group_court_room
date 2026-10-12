import { Navigate, Route, Routes } from "react-router-dom";

import CaseDetailPage from "./pages/CaseDetailPage";
import CourtsPage from "./pages/CourtsPage";
import DashboardPage from "./pages/DashboardPage";
import FilePage from "./pages/FilePage";
import HomePage from "./pages/HomePage";
import InvitePage from "./pages/InvitePage";
import JuryPage from "./pages/JuryPage";
import RapSheetPage from "./pages/RapSheetPage";
import VerdictPage from "./pages/VerdictPage";

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<HomePage />} />
      {/* The creator's court. */}
      <Route path="/file" element={<FilePage />} />
      <Route path="/cases" element={<DashboardPage />} />
      <Route path="/cases/:id" element={<CaseDetailPage />} />
      <Route path="/courts" element={<CourtsPage />} />
      <Route path="/rap-sheet" element={<RapSheetPage />} />
      {/* Capability links: the token is the whole credential. */}
      <Route path="/invite/:token" element={<InvitePage />} />
      <Route path="/jury/:token" element={<JuryPage />} />
      <Route path="/verdict/:token" element={<VerdictPage />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
