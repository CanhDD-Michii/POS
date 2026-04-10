import  React  from 'react'
import { createRoot } from 'react-dom/client'
import { RecoilRoot } from 'recoil';
import { BrowserRouter } from 'react-router-dom';
import './styles/index.css';
import App from './App.jsx';

createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <RecoilRoot>
      <BrowserRouter>
        <App></App>
      </BrowserRouter>
    </RecoilRoot>
  </React.StrictMode>
);
