using System.IO;
using Microsoft.AspNetCore.Hosting;

namespace Microsoft.SourceBrowser.SourceIndexServer
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var host = BuildWebHost(args);
            host.Run();
        }

        public static IWebHost BuildWebHost(string[] args)
            => new WebHostBuilder()
                .UseKestrel()
                .UseStartup<Startup>()
                .UseIISIntegration()
                .UseContentRoot(Directory.GetCurrentDirectory())
                .Build();
    }
}
