import XCTest
import WebKit

extension AdapterWorkflowTests {
    @MainActor func testMetadataIsPerFileActiveBranchOnlyAndNeverLeaksAuthentication() async throws {
        let web = try await fixture("""
        <script>
        history.replaceState({},'', '/c/11111111-1111-1111-1111-111111111111');
        function image(id,size,v2){return {content_type:'image_asset_pointer',asset_pointer:'sediment://'+id,metadata:{generation:{gen_size:size,gen_size_v2:v2}}};}
        function node(id,parent,role,parts){return {parent,message:{id,author:{role},content:{parts}}};}
        const conv={current_node:'final',mapping:{
          reference:node('reference',null,'user',[image('file_reference','image',32)]),
          a:node('a','reference','tool',[image('file_a','smimage',24),image('file_b','image','32')]),
          abandoned:node('abandoned','a','assistant',[image('file_wrong','image',32)]),
          final:node('final','a','assistant',[image('file_a'),image('file_b'),image('file_unknown'),image('file_conflict','image',24)])
        }};
        window.fetch=async(url,options)=>({ok:true,json:async()=>url==='/api/auth/session'?{accessToken:'never-return-this-token'}:conv});
        </script>
        """)
        defer { web.stopLoading() }
        let result = try await call(web,"generationMetadata")
        let records = result["images"] as! [[String:Any]]
        XCTAssertEqual(Set(records.map { $0["fileID"] as! String }), ["file_a","file_b","file_unknown","file_conflict"])
        XCTAssertEqual(records.first { $0["fileID"] as? String == "file_a" }?["genSizeV2"] as? String,"24")
        XCTAssertEqual(records.first { $0["fileID"] as? String == "file_b" }?["genSizeV2"] as? String,"32")
        XCTAssertFalse(String(describing:result).contains("never-return-this-token"))
    }
    @MainActor func testUnavailableMetadataDoesNotReturnInventedModel() async throws {
        let web = try await fixture("""
        <script>history.replaceState({},'', '/c/11111111-1111-1111-1111-111111111111');window.fetch=async()=>({ok:false,status:401});</script>
        """)
        defer { web.stopLoading() }
        do { _ = try await call(web,"generationMetadata"); XCTFail("Should not fabricate model evidence") }
        catch { XCTAssertTrue(String(describing:error).contains("metadata-session-unavailable")) }
    }
}
