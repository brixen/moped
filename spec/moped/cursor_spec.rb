require "spec_helper"

describe Moped::Cursor do
  let(:socket) { mock Moped::Socket }
  let(:query_operation) { Moped::Protocol::Query.allocate }
  let(:cursor) { Moped::Cursor.new(socket, query_operation) }

  describe "#initialize" do
    it "stores the socket" do
      cursor.socket.should eq socket
    end

    it "stores a copy of the query operation" do
      query_operation.should_receive(:dup).and_return(query_operation)
      cursor.query_op.should eq query_operation
    end

    describe "the get_more operation" do
      it "inherits the query's database" do
        cursor.get_more_op.database.should eq query_operation.database
      end

      it "inherits the query's collection" do
        cursor.get_more_op.collection.should eq query_operation.collection
      end

      it "inherits the query's limit" do
        cursor.get_more_op.limit.should eq query_operation.limit
      end
    end
  end

  describe "#more?" do
    context "when get more operation's cursor id is 0" do
      it "returns false" do
        cursor.get_more_op.cursor_id = 0
        cursor.more?.should be_false
      end
    end
    context "when get more operation's cursor id is not 0" do
      it "returns true" do
        cursor.get_more_op.cursor_id = 123
        cursor.more?.should be_true
      end
    end
  end

  describe "#limited?" do
    context "when original query's limit is greater than 0" do
      before do
        query_operation.limit = 20
      end

      it "returns true" do
        cursor.should be_limited
      end
    end

    context "when original query's limit is not greater than 0" do
      before do
        query_operation.limit = 0
      end

      it "returns true" do
        cursor.should_not be_limited
      end
    end
  end

  describe "#execute" do
    let(:reply) do
      Moped::Protocol::Reply.allocate.tap do |reply|
        reply.cursor_id = 123
        reply.count = 1
        reply.documents = [{"a" => 1}]
      end
    end

    before do
      socket.stub(execute: reply)
    end

    context "when query is limited" do
      before do
        query_operation.limit = 21
        cursor.execute query_operation
      end

      it "updates the more operation's limit" do
        cursor.get_more_op.limit.should eq 20
      end

      it "sets the kill cursor operation's cursor id" do
        cursor.kill_cursor_op.cursor_ids.should eq [reply.cursor_id]
      end

      it "sets the more operation's cursor id" do
        cursor.get_more_op.cursor_id.should eq reply.cursor_id
      end
    end

    context "when query is limited" do
      before do
        query_operation.limit = 0
        cursor.execute query_operation
      end

      it "does not update the more operation's limit" do
        cursor.get_more_op.limit.should eq query_operation.limit
      end

      it "sets the kill cursor operation's cursor id" do
        cursor.kill_cursor_op.cursor_ids.should eq [reply.cursor_id]
      end

      it "sets the more operation's cursor id" do
        cursor.get_more_op.cursor_id.should eq reply.cursor_id
      end
    end

    it "returns the documents" do
      cursor.execute(query_operation).should eq reply.documents
    end
  end

  describe "#each" do

    context "when query returns all available documents" do
      let(:reply) do
        Moped::Protocol::Reply.allocate.tap do |reply|
          reply.cursor_id = 0
          reply.count = 21
          reply.documents = [{"a" => 1}]
        end
      end

      before do
        socket.stub(execute: reply)
      end

      it "yields each document" do
        results = []
        cursor.each { |doc| results << doc }
        results.should eq reply.documents
      end

      it "does not get more" do
        socket.should_receive(:execute).once
        cursor.each {}
      end

      it "does not kill the cursor" do
        cursor.should_receive(:kill).never
        cursor.each {}
      end
    end

    context "when query is unlimited" do
      let(:reply) do
        Moped::Protocol::Reply.allocate.tap do |reply|
          reply.cursor_id = 10
          reply.count = 10
          reply.documents = [{"a" => 1}]
        end
      end

      let(:get_more_reply) do
        Moped::Protocol::Reply.allocate.tap do |reply|
          reply.cursor_id = 0
          reply.count = 21
          reply.documents = [{"a" => 1}]
        end
      end

      before do
        socket.stub(:execute).and_return(reply, get_more_reply)
      end

      it "yields each document" do
        results = []
        cursor.each { |doc| results << doc }
        results.should eq reply.documents + get_more_reply.documents
      end

      it "gets more twice" do
        socket.should_receive(:execute).twice
        cursor.each {}
      end

      it "does not kill the cursor" do
        cursor.should_receive(:kill).never
        cursor.each {}
      end
    end

    context "when query is limited" do
      let(:reply) do
        Moped::Protocol::Reply.allocate.tap do |reply|
          reply.cursor_id = 10
          reply.count = 10
          reply.documents = [{"a" => 1}]
        end
      end

      let(:get_more_reply) do
        Moped::Protocol::Reply.allocate.tap do |reply|
          reply.cursor_id = 10
          reply.count = 10
          reply.documents = [{"a" => 1}]
        end
      end

      before do
        query_operation.limit = 20
        socket.stub(:execute).and_return(reply, get_more_reply)
      end

      it "yields each document" do
        results = []
        cursor.each { |doc| results << doc }
        results.should eq reply.documents + get_more_reply.documents
      end

      it "gets more twice" do
        socket.should_receive(:execute).at_least(2)
        cursor.each {}
      end

      it "kills the cursor" do
        cursor.should_receive(:kill).once
        cursor.each {}
      end
    end

  end
end
