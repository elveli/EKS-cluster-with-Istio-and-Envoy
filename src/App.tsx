import { useState, useEffect, useRef } from 'react';
import ReactMarkdown from 'react-markdown';
import mermaid from 'mermaid';
import { Terminal, FileCode2, BookOpen, Server } from 'lucide-react';
import readmeContent from '../README.md?raw';
import mainTfContent from '../terraform/main.tf?raw';
import variablesTfContent from '../terraform/variables.tf?raw';
import outputsTfContent from '../terraform/outputs.tf?raw';

function MermaidChart({ chart }: { chart: string }) {
  const containerRef = useRef<HTMLDivElement>(null);
  
  useEffect(() => {
    if (containerRef.current) {
      mermaid.initialize({
        startOnLoad: true,
        theme: 'default',
        securityLevel: 'loose',
      });
      // Generate a unique ID for the mermaid container
      const id = `mermaid-${Math.random().toString(36).substr(2, 9)}`;
      containerRef.current.id = id;
      
      mermaid.render(id + '-svg', chart).then((result) => {
        if (containerRef.current) {
          containerRef.current.innerHTML = result.svg;
        }
      }).catch(e => {
        console.error("Mermaid rendering failed", e);
      });
    }
  }, [chart]);

  return <div ref={containerRef} className="my-8 flex justify-center bg-white p-4 rounded-xl shadow-sm border border-slate-200" />;
}

export default function App() {
  const [activeTab, setActiveTab] = useState('readme');

  const tabs = [
    { id: 'readme', label: 'Instructions', icon: BookOpen, content: readmeContent, isMarkdown: true },
    { id: 'main', label: 'main.tf', icon: Server, content: mainTfContent, isMarkdown: false },
    { id: 'variables', label: 'variables.tf', icon: FileCode2, content: variablesTfContent, isMarkdown: false },
    { id: 'outputs', label: 'outputs.tf', icon: Terminal, content: outputsTfContent, isMarkdown: false },
  ];

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900 font-sans">
      <header className="bg-white border-b border-slate-200 sticky top-0 z-10">
        <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center h-16">
            <div className="flex items-center gap-2">
              <Server className="w-6 h-6 text-blue-600" />
              <h1 className="text-xl font-semibold tracking-tight">EKS Istio Showcase</h1>
            </div>
          </div>
          <nav className="flex space-x-8" aria-label="Tabs">
            {tabs.map((tab) => {
              const Icon = tab.icon;
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`
                    flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm
                    ${
                      activeTab === tab.id
                        ? 'border-blue-500 text-blue-600'
                        : 'border-transparent text-slate-500 hover:text-slate-700 hover:border-slate-300'
                    }
                  `}
                >
                  <Icon className="w-4 h-4" />
                  {tab.label}
                </button>
              );
            })}
          </nav>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden">
          {tabs.map((tab) => (
            <div
              key={tab.id}
              className={`${activeTab === tab.id ? 'block' : 'hidden'} p-6 sm:p-8`}
            >
              {tab.isMarkdown ? (
                <div className="prose prose-slate max-w-none prose-headings:font-semibold prose-a:text-blue-600 hover:prose-a:text-blue-500 prose-pre:bg-slate-900 prose-pre:text-slate-50">
                  <ReactMarkdown
                    components={{
                      code(props) {
                        const {children, className, node, ...rest} = props;
                        const match = /language-(\w+)/.exec(className || '');
                        if (match && match[1] === 'mermaid') {
                          return <MermaidChart chart={String(children).replace(/\n$/, '')} />;
                        }
                        return <code {...rest} className={className}>{children}</code>;
                      }
                    }}
                  >
                    {tab.content}
                  </ReactMarkdown>
                </div>
              ) : (
                <pre className="bg-slate-900 text-slate-50 p-6 rounded-lg overflow-x-auto text-sm font-mono leading-relaxed">
                  <code>{tab.content}</code>
                </pre>
              )}
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}
